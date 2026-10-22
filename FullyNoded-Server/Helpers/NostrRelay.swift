//
//  NostrRelay.swift
//  FullyNoded-Server
//
//  A small private nostr relay (NIP-01 over WebSocket) for Nostr Connect, so Fully Noded can
//  reach this node quickly on the local network instead of over Tor.
//
//  • Ephemeral only: events are forwarded to matching subscriptions and never stored, so a REQ
//    gets an immediate EOSE.
//  • Only allowed keys may publish (this server's bridge key and paired devices). Anyone who
//    can reach the port can subscribe, but every payload is NIP-44 encrypted.
//  • Built on Network.framework: no dependencies.
//

import Foundation
import Network
import CryptoKit

final class NostrRelay {
    static let shared = NostrRelay()

    struct Status {
        let isRunning: Bool
        let port: UInt16
        let connections: Int
        let eventsRelayed: Int
        let lastError: String?
        /// Serving wss:// (TLS with the pinned self-signed certificate).
        let tls: Bool
    }

    /// Public keys allowed to publish. Read on the relay's queue.
    var allowedAuthors: () -> Set<String> = { [] }
    /// Called on the main queue whenever the status changes.
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "FullyNoded-Server.NostrRelay")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var port: UInt16 = 0
    private var tls = false
    private var eventsRelayed = 0
    private var lastError: String?

    private init() {}

    private final class Client {
        let connection: NWConnection
        var subscriptions: [String: [Filter]] = [:]
        init(_ connection: NWConnection) { self.connection = connection }
    }

    /// The parts of a NIP-01 filter Nostr Connect uses.
    private struct Filter {
        let ids: Set<String>?
        let kinds: Set<Int>?
        let authors: Set<String>?
        let pTags: Set<String>?
        let since: Int?
        let until: Int?

        init?(_ json: Any) {
            guard let d = json as? [String: Any] else { return nil }
            ids = (d["ids"] as? [String]).map(Set.init)
            kinds = (d["kinds"] as? [NSNumber]).map { Set($0.map(\.intValue)) }
            authors = (d["authors"] as? [String]).map(Set.init)
            pTags = (d["#p"] as? [String]).map(Set.init)
            since = (d["since"] as? NSNumber)?.intValue
            until = (d["until"] as? NSNumber)?.intValue
        }

        func matches(_ e: NostrEvent) -> Bool {
            if let ids = ids, !ids.contains(e.id) { return false }
            if let kinds = kinds, !kinds.contains(e.kind) { return false }
            if let authors = authors, !authors.contains(e.pubkey) { return false }
            if let pTags = pTags, !e.tags.contains(where: { $0.first == "p" && $0.count > 1 && pTags.contains($0[1]) }) { return false }
            if let since = since, e.created_at < since { return false }
            if let until = until, e.created_at > until { return false }
            return true
        }
    }

    // MARK: Control

    /// Listens on `port`: wss:// with `identity` (RelayTLS), else plain ws://.
    func start(port: UInt16, identity: SecIdentity? = nil) throws {
        stop()
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 8 * 1024 * 1024
        let parameters: NWParameters
        if let identity = identity, let secIdentity = sec_identity_create(identity) {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
        } else {
            parameters = NWParameters.tcp
        }
        parameters.allowLocalEndpointReuse = true
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NIP44.Failure.invalidKey }
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                self.lastError = "Relay stopped: \(error.localizedDescription)"
                self.listener = nil
                self.log("stopped: \(error.localizedDescription)")
            case .ready:
                self.lastError = nil
                self.log("listening on port \(self.port) (\(self.tls ? "wss, pinned certificate" : "ws"))")
            default:
                break
            }
            self.changed()
        }
        queue.sync {
            self.port = port
            self.tls = identity != nil
            self.listener = listener
            self.lastError = nil
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.connection.cancel() }
            clients.removeAll()
        }
        changed()
    }

    func status() -> Status {
        queue.sync {
            Status(isRunning: listener != nil, port: port, connections: clients.count,
                   eventsRelayed: eventsRelayed, lastError: lastError, tls: tls)
        }
    }

    private func changed() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: Connections (on `queue`)

    /// Enough for a few devices and the bridge; refuses floods once the port is reachable from
    /// the internet (ngrok, port forwarding).
    private static let maxConnections = 64

    private func accept(_ connection: NWConnection) {
        guard clients.count < Self.maxConnections else {
            log("refused \(connection.endpoint): \(Self.maxConnections) connections already")
            connection.cancel()
            return
        }
        let client = Client(connection)
        clients[ObjectIdentifier(client)] = client
        log("client connected: \(connection.endpoint) (\(clients.count) open)")
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self = self, let client = client else { return }
            switch state {
            case .failed, .cancelled:
                self.clients[ObjectIdentifier(client)] = nil
                self.log("client disconnected: \(client.connection.endpoint) (\(self.clients.count) open)")
                self.changed()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(client)
        changed()
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            guard let self = self, let client = client else { return }
            if let error = error {
                if case .posix(let code) = error, code == .ECANCELED { return }
                client.connection.cancel()
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .close {
                client.connection.cancel()
                return
            }
            if let data = data, !data.isEmpty, metadata?.opcode == .text || metadata?.opcode == .binary {
                self.handle(data, from: client)
            }
            self.receive(client)
        }
    }

    private func send(_ message: [Any], to client: Client) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func handle(_ data: Data, from client: Client) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = message.first as? String else {
            send(["NOTICE", "invalid message"], to: client)
            return
        }
        switch type {
        case "EVENT":
            guard message.count >= 2, let event = NostrEvent(json: message[1]) else {
                send(["NOTICE", "invalid event"], to: client)
                return
            }
            publish(event, from: client)

        case "REQ":
            guard message.count >= 3, let subscriptionID = message[1] as? String, subscriptionID.count <= 64 else {
                send(["NOTICE", "invalid REQ"], to: client)
                return
            }
            let filters = message.dropFirst(2).compactMap(Filter.init)
            client.subscriptions[subscriptionID] = filters
            // Nothing is stored, so there's nothing to replay.
            send(["EOSE", subscriptionID], to: client)

        case "CLOSE":
            if message.count >= 2, let subscriptionID = message[1] as? String {
                client.subscriptions[subscriptionID] = nil
                send(["CLOSED", subscriptionID, ""], to: client)
            }

        default:
            send(["NOTICE", "unsupported: \(type)"], to: client)
        }
    }

    private func publish(_ event: NostrEvent, from sender: Client) {
        guard event.isValid else {
            send(["OK", event.id, false, "invalid: bad id or signature"], to: sender)
            log("rejected event from \(event.pubkey.prefix(8))…: bad id or signature")
            return
        }
        guard (20_000..<30_000).contains(event.kind) else {
            send(["OK", event.id, false, "blocked: this relay only forwards ephemeral events"], to: sender)
            log("rejected kind \(event.kind) event from \(event.pubkey.prefix(8))…: not ephemeral")
            return
        }
        guard allowedAuthors().contains(event.pubkey) else {
            send(["OK", event.id, false, "restricted: not paired with this node"], to: sender)
            log("rejected event from \(event.pubkey.prefix(8))…: not paired with this node")
            return
        }
        send(["OK", event.id, true, ""], to: sender)
        let json = event.jsonObject
        var delivered = 0
        for client in clients.values {
            for (subscriptionID, filters) in client.subscriptions where filters.contains(where: { $0.matches(event) }) {
                send(["EVENT", subscriptionID, json], to: client)
                delivered += 1
            }
        }
        log("relayed kind \(event.kind) from \(event.pubkey.prefix(8))… to \(delivered) subscriber\(delivered == 1 ? "" : "s")\(delivered == 0 ? " (nobody listening: is the bridge connected?)" : "")")
        eventsRelayed += 1
        changed()
    }

    // MARK: Addresses

    /// This Mac's IPv4 addresses on the local network (Wi-Fi / Ethernet), for the pairing link.
    /// Console log for Nostr Connect (debug builds only).
    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[nostr-relay] \(message())")
        #endif
    }

    static func lanAddresses() -> [String] {
        ipv4Addresses().filter { $0.interface.hasPrefix("en") && !isCGNAT($0.address) }.map(\.address)
    }

    /// VPN addresses in 100.64.0.0/10, which Tailscale (and Headscale, NetBird…) hand out: a
    /// paired device on the same tailnet reaches the relay through them from anywhere.
    static func vpnAddresses() -> [String] {
        ipv4Addresses().filter { isCGNAT($0.address) }.map(\.address)
    }

    private static func isCGNAT(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    private static func ipv4Addresses() -> [(interface: String, address: String)] {
        var result: [(interface: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((name, String(cString: host)))
            }
        }
        return result
    }
}

// MARK: - TLS identity

/// The relay's TLS identity: an EC key and self-signed certificate made once with openssl
/// (Scripts/CreateRelayCert.command), stored encrypted in the Keychain and loaded into memory
/// only. Fully Noded pins the certificate's SHA-256 (in the pairing link), so it needs no CA.
enum RelayTLS {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let keychainKey = "nostrConnectRelayIdentity"

    /// wss:// needs macOS 15: older systems can only import the identity into the login keychain.
    static var isSupported: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    /// The identity and its certificate's SHA-256 (hex), creating them the first time.
    /// Completion on the main queue.
    static func load(completion: @escaping (Result<(identity: SecIdentity, fingerprint: String), Error>) -> Void) {
        let finish: (Result<(identity: SecIdentity, fingerprint: String), Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        guard isSupported else {
            finish(.failure(Failure("Encrypted connections (wss) need macOS 15 or later.")))
            return
        }
        if let stored = KeyChain.getData(keychainKey), let plain = Crypto.decrypt(stored),
           let saved = try? JSONDecoder().decode(Stored.self, from: plain), let p12 = Data(base64Encoded: saved.p12) {
            finish(importIdentity(p12, password: saved.password))
            return
        }
        create(completion: finish)
    }

    /// Replaces the identity (devices must pair again).
    static func reset() {
        _ = KeyChain.remove(key: keychainKey)
    }

    private struct Stored: Codable {
        let p12: String
        let password: String
    }

    private static func create(completion: @escaping (Result<(identity: SecIdentity, fingerprint: String), Error>) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("relay-cert-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            completion(.failure(Failure("Couldn't create a folder for the relay certificate: \(error.localizedDescription)")))
            return
        }
        let password = NostrHex.encode(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        ScriptUtil.runScript(script: .createRelayCert, env: ["OUT_DIR": dir.path, "P12_PASSWORD": password], args: nil) { output, _, errorMessage in
            defer { try? FileManager.default.removeItem(at: dir) }
            guard let p12 = try? Data(contentsOf: dir.appendingPathComponent("identity.p12")) else {
                completion(.failure(Failure("openssl couldn't create the relay certificate. \(errorMessage ?? output ?? "")")))
                return
            }
            let stored = Stored(p12: p12.base64EncodedString(), password: password)
            guard let json = try? JSONEncoder().encode(stored), let encrypted = Crypto.encrypt(json),
                  KeyChain.set(encrypted, forKey: keychainKey) else {
                completion(.failure(Failure("Couldn't save the relay certificate.")))
                return
            }
            completion(importIdentity(p12, password: password))
        }
    }

    private static func importIdentity(_ p12: Data, password: String) -> Result<(identity: SecIdentity, fingerprint: String), Error> {
        guard #available(macOS 15, *) else { return .failure(Failure("Encrypted connections (wss) need macOS 15 or later.")) }
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password,
                                      kSecImportToMemoryOnly as String: true]
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String] else {
            return .failure(Failure("Couldn't load the relay certificate (\(status))."))
        }
        let identity = value as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate = certificate else {
            return .failure(Failure("The relay certificate has no certificate."))
        }
        return .success((identity, NostrTLS.fingerprint(certificate)))
    }
}
