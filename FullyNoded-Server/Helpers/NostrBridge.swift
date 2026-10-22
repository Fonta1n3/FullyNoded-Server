//
//  NostrBridge.swift
//  FullyNoded-Server
//
//  Nostr Connect bridge: answers Fully Noded's RPC requests that arrive over nostr relays.
//
//  For every relay (this Mac's own relay and any public relays added) it subscribes to events of
//  NostrEvent.rpcKind addressed to the bridge key. A request from a paired device is decrypted
//  (NIP-44), put back together from its frames, sent to the local Bitcoin Core on the pairing's
//  network, and the response goes back the same way, encrypted to that device.
//
//  Pairing hands a device a fresh client secret once (in the link). Only its public key is kept,
//  so removing a pairing cuts that device off for good.
//

import Foundation

final class NostrBridge: NSObject {
    static let shared = NostrBridge()

    struct Pairing: Codable, Identifiable, Equatable {
        var id: String { pubkey }
        let pubkey: String
        var label: String
        /// Network whose node this device talks to (main, test, testnet4, signet, regtest).
        let chain: String
        let created: Date
        var lastSeen: Date?
    }

    enum RelayState: Equatable {
        case connecting, connected, failed(String)
    }

    /// Called on the main queue when pairings or connection states change.
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "FullyNoded-Server.NostrBridge")
    private var keys: NostrKeys?
    private var pairings: [Pairing] = []
    private var running = false
    private var relays: [String: RelayConnection] = [:]
    private var relayStates: [String: RelayState] = [:]
    private var conversationKeys: [String: Data] = [:]
    private var reassemblers: [String: NostrRPCReassembler] = [:]
    private var seenEvents: [String: Date] = [:]
    /// Each device's requests ("pubkey:id"): being answered, or answered (and when).
    private var requests: [String: (answered: Bool, at: Date)] = [:]
    /// When a duplicate request was last answered from the outbox (one reply per burst).
    private var duplicateReplies: [String: Date] = [:]
    /// Answers sent, kept for resends ("pubkey:id").
    private let outbox = NostrRPCOutbox()
    /// The relay each device was last heard on.
    private var lastRelay: [String: RelayConnection] = [:]
    /// Events sent and not yet accepted, for retrying ones a relay turns away.
    private var unconfirmed: [String: (message: [Any], relay: RelayConnection, attempts: Int, sent: Date)] = [:]
    private var tick: DispatchSourceTimer?
    /// SHA-256 of this Mac's relay's certificate, when it serves wss:// (pinned on loopback).
    private var localPin: String?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    private override init() {
        super.init()
        queue.sync {
            keys = Self.loadOrCreateKeys()
            pairings = Self.loadPairings()
        }
    }

    // MARK: Public API (any thread)

    var publicKey: String { queue.sync { keys?.publicKey ?? "" } }

    var allPairings: [Pairing] { queue.sync { pairings } }

    var pairedPublicKeys: Set<String> {
        queue.sync { Set(pairings.map(\.pubkey) + [keys?.publicKey].compactMap { $0 }) }
    }

    func states() -> [String: RelayState] { queue.sync { relayStates } }

    var isRunning: Bool { queue.sync { running } }

    /// Connects to `urls` (replacing any previous set). `pin`: this Mac's relay's certificate.
    func start(relays urls: [String], pin: String? = nil) {
        queue.async {
            self.running = true
            if self.localPin != pin {
                // The relay's certificate changed: reconnect to it with the new pin.
                self.relays.values.forEach { $0.close() }
                self.relays.removeAll()
                self.relayStates.removeAll()
                self.localPin = pin
            }
            let wanted = Set(urls)
            for (url, connection) in self.relays where !wanted.contains(url) {
                connection.close()
                self.relays[url] = nil
                self.relayStates[url] = nil
            }
            for url in urls where self.relays[url] == nil {
                self.connect(url)
            }
            self.startTick()
            self.changed()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.tick?.cancel()
            self.tick = nil
            self.relays.values.forEach { $0.close() }
            self.relays.removeAll()
            self.relayStates.removeAll()
            self.changed()
        }
    }

    /// A new pairing: returns the link to show Fully Noded once. `pin`: this Mac's relay's
    /// certificate when it serves wss://, so Fully Noded trusts exactly that certificate.
    func pair(label: String, chain: String, relays urls: [String], pin: String? = nil) -> String? {
        queue.sync {
            guard let keys = keys, let client = NostrKeys.generate(), !urls.isEmpty else { return nil }
            pairings.append(Pairing(pubkey: client.publicKey, label: label, chain: chain, created: Date(), lastSeen: nil))
            savePairings()
            changed()
            return NostrConnectURI(bridgePubkey: keys.publicKey, relays: urls, clientSecret: client.secretHex,
                                   label: label.isEmpty ? nil : label, chain: chain, certSHA256: pin).string
        }
    }

    func unpair(_ pubkey: String) {
        queue.async {
            self.pairings.removeAll { $0.pubkey == pubkey }
            self.conversationKeys[pubkey] = nil
            self.reassemblers[pubkey] = nil
            self.lastRelay[pubkey] = nil
            self.savePairings()
            self.changed()
        }
    }

    private func changed() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: Storage (Keychain, encrypted with the app's key)

    private static let keyName = "nostrConnectBridgeKey"
    private static let pairingsName = "nostrConnectPairings"

    private static func loadOrCreateKeys() -> NostrKeys? {
        if let stored = KeyChain.getData(keyName), let secret = Crypto.decrypt(stored), let keys = NostrKeys(secret: secret) {
            return keys
        }
        guard let keys = NostrKeys.generate(), let encrypted = Crypto.encrypt(keys.secret) else { return nil }
        _ = KeyChain.set(encrypted, forKey: keyName)
        return keys
    }

    private static func loadPairings() -> [Pairing] {
        guard let stored = KeyChain.getData(pairingsName), let json = Crypto.decrypt(stored) else { return [] }
        return (try? JSONDecoder().decode([Pairing].self, from: json)) ?? []
    }

    private func savePairings() {
        guard let json = try? JSONEncoder().encode(pairings), let encrypted = Crypto.encrypt(json) else { return }
        _ = KeyChain.set(encrypted, forKey: Self.pairingsName)
    }

    // MARK: Relays (on `queue`)

    private func connect(_ url: String) {
        guard let keys = keys, let u = URL(string: url) else {
            relayStates[url] = .failed("Invalid relay URL")
            return
        }
        let connection = RelayConnection(url: u, session: session, queue: queue)
        connection.onOpen = { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            self.log("relay open: \(url), subscribed to kind \(NostrEvent.rpcKind) for \(keys.publicKey.prefix(8))…")
            self.relayStates[url] = .connected
            let filter: [String: Any] = ["kinds": [NostrEvent.rpcKind], "#p": [keys.publicKey],
                                         "since": Int(Date().timeIntervalSince1970) - 60]
            connection.send(["REQ", "fn-bridge", filter])
            self.changed()
        }
        connection.onMessage = { [weak self, weak connection] message in
            guard let self = self, let connection = connection else { return }
            self.handle(message, relay: connection)
        }
        connection.onClose = { [weak self] reason in
            guard let self = self, self.running, self.relays[url] != nil else { return }
            self.log("relay closed: \(url) (\(reason)), retrying in 5 s")
            self.relayStates[url] = .failed(reason)
            self.relays[url] = nil
            self.changed()
            // Try again shortly: a relay restarting, Wi-Fi changing, a laptop waking up.
            self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, self.running, self.relays[url] == nil else { return }
                self.connect(url)
            }
        }
        relays[url] = connection
        relayStates[url] = .connecting
        log("relay connecting: \(url)")
        connection.open()
    }

    private func handle(_ message: [Any], relay: RelayConnection) {
        if message.first as? String == "OK" {
            handleOK(message)
            return
        }
        guard message.first as? String == "EVENT", message.count >= 3,
              let event = NostrEvent(json: message[2]),
              event.kind == NostrEvent.rpcKind,
              let keys = keys, event.recipient == keys.publicKey else { return }

        // Each event once, recent ones only.
        let now = Date()
        let sender = "\(event.pubkey.prefix(8))…"
        seenEvents = seenEvents.filter { now.timeIntervalSince($0.value) < 600 }
        guard seenEvents[event.id] == nil else { return }   // the same event via another relay
        guard abs(now.timeIntervalSince1970 - Double(event.created_at)) < 600 else {
            log("dropped event from \(sender): created \(Int(now.timeIntervalSince1970) - event.created_at) s from now (clock skew or replay)")
            return
        }
        guard let index = pairings.firstIndex(where: { $0.pubkey == event.pubkey }) else {
            log("dropped event from \(sender): not a paired device")
            return
        }
        guard event.isValid else {
            log("dropped event from \(sender): bad id or signature")
            return
        }
        seenEvents[event.id] = now

        guard let conversationKey = conversationKey(for: event.pubkey),
              let plaintext = try? NIP44.decrypt(event.content, conversationKey: conversationKey) else {
            log("dropped event from \(pairings[index].label): couldn't decrypt (NIP-44)")
            return
        }
        guard let frame = try? JSONDecoder().decode(NostrRPCFrame.self, from: plaintext) else {
            log("dropped event from \(pairings[index].label): not an RPC frame")
            return
        }

        lastRelay[event.pubkey] = relay
        if pairings[index].lastSeen.map({ now.timeIntervalSince($0) > 60 }) ?? true {
            pairings[index].lastSeen = now
            savePairings()
            changed()
        }
        let pairing = pairings[index]
        let key = "\(event.pubkey):\(frame.id)"

        // The device is missing frames of an answer: send those again.
        if let seqs = frame.resend {
            let frames = outbox.frames(key, seqs: seqs)
            log("\(pairing.label) asked again for \(seqs.count) frame(s) of \(frame.id.prefix(8))\(frames.isEmpty ? ", no longer stored" : "")")
            send(frames, to: event.pubkey, conversationKey: conversationKey, relay: relay)
            return
        }
        guard !frame.isControl else { return }

        // A request already received: ack it again, and resend its answer if there is one
        // (the device got neither). Once per burst of its frames.
        if let state = requests[key] {
            guard duplicateReplies[key].map({ now.timeIntervalSince($0) > 2 }) ?? true else { return }
            duplicateReplies[key] = now
            log("repeated request \(frame.id.prefix(8)) from \(pairing.label): \(state.answered ? "sending the stored answer again" : "still working on it")")
            send([.ack(id: frame.id)], to: event.pubkey, conversationKey: conversationKey, relay: relay)
            if state.answered {
                send(outbox.frames(key), to: event.pubkey, conversationKey: conversationKey, relay: relay)
            }
            return
        }

        let reassembler = reassemblers[event.pubkey] ?? NostrRPCReassembler()
        reassemblers[event.pubkey] = reassembler
        guard let (first, body) = reassembler.add(frame) else {
            log("frame \(frame.seq + 1)/\(frame.total) of request \(frame.id.prefix(8)) from \(pairing.label)")
            return
        }

        requests[key] = (false, now)
        send([.ack(id: first.id)], to: event.pubkey, conversationKey: conversationKey, relay: relay)
        #if DEBUG
        let started = Date()
        let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let method = request?["method"] as? String ?? "?"
        log("→ \(method)\(first.path.map { $0.isEmpty ? "" : " \($0)" } ?? "") from \(pairing.label) on \(pairing.chain) via \(relay.url.absoluteString) (\(first.total) frame\(first.total == 1 ? "" : "s")\(first.deflate == true ? ", compressed" : "")) params: \(request?["params"] ?? "none")")
        #endif
        forward(body: body, path: first.path ?? "", timeout: first.timeout ?? 60, chain: pairing.chain) { [weak self] status, response, error in
            guard let self = self else { return }
            #if DEBUG
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let rpcError = ((try? JSONSerialization.jsonObject(with: response)) as? [String: Any])?["error"] as? [String: Any]
            let outcome = error ?? rpcError.map { "RPC error \($0["code"] ?? ""): \($0["message"] ?? "")" } ?? "ok"
            self.log("← \(method) HTTP \(status) \(outcome), \(response.count) bytes (\(ms) ms)")
            #endif
            self.queue.async {
                let frames = NostrRPCFrame.frames(id: first.id, body: response, status: status, error: error)
                self.outbox.store(key, frames)
                self.requests[key] = (true, Date())
                // Answer on the relay the device was last heard on.
                self.send(frames, to: pairing.pubkey, conversationKey: conversationKey,
                          relay: self.lastRelay[pairing.pubkey] ?? relay)
            }
        }
    }

    private func conversationKey(for pubkey: String) -> Data? {
        if let cached = conversationKeys[pubkey] { return cached }
        guard let keys = keys, let key = try? NIP44.conversationKey(secret: keys.secret, publicKey: pubkey) else { return nil }
        conversationKeys[pubkey] = key
        return key
    }

    /// Encrypts and publishes frames to one device, paced a little when there are several so a
    /// public relay doesn't rate-limit the burst. Each send is a fresh event (a relay that
    /// remembers event ids won't swallow a resend).
    private func send(_ frames: [NostrRPCFrame], to pubkey: String, conversationKey: Data, relay: RelayConnection) {
        guard let keys = keys, !frames.isEmpty else { return }
        for (i, frame) in frames.enumerated() {
            let publish = { [weak self] in
                guard let self = self,
                      let json = try? JSONEncoder().encode(frame),
                      let content = try? NIP44.encrypt(json, conversationKey: conversationKey),
                      let event = NostrEvent.make(keys: keys, kind: NostrEvent.rpcKind, tags: [["p", pubkey]], content: content) else { return }
                let message: [Any] = ["EVENT", event.jsonObject]
                self.unconfirmed[event.id] = (message, relay, 0, Date())
                relay.send(message)
                if frame.ack == true {
                    self.log("ack \(frame.id.prefix(8)) sent")
                } else if let seqs = frame.resend {
                    self.log("asked for \(seqs.count) missing frame(s) of \(frame.id.prefix(8))")
                } else {
                    self.log("reply frame \(frame.seq + 1)/\(frame.total) of \(frame.id.prefix(8)) sent via \(relay.url.absoluteString)")
                }
            }
            if i < 8 {
                publish()
            } else {
                queue.asyncAfter(deadline: .now() + Double(i - 7) * 0.05, execute: publish)
            }
        }
    }

    /// A relay's answer to a published event: retry the ones it turned away for now.
    private func handleOK(_ message: [Any]) {
        guard message.count >= 3, let id = message[1] as? String, let accepted = message[2] as? Bool else { return }
        guard !accepted, let entry = unconfirmed[id] else {
            unconfirmed[id] = nil
            return
        }
        let reason = message.count > 3 ? (message[3] as? String ?? "") : ""
        let transient = reason.hasPrefix("rate-limited") || reason.hasPrefix("error")
        guard transient, entry.attempts < 3 else {
            unconfirmed[id] = nil
            log("relay \(entry.relay.url.absoluteString) rejected an event: \(reason)")
            return
        }
        unconfirmed[id] = (entry.message, entry.relay, entry.attempts + 1, entry.sent)
        let delay = Double(1 << entry.attempts)
        log("relay \(entry.relay.url.absoluteString) said \"\(reason)\", retrying in \(Int(delay)) s")
        queue.asyncAfter(deadline: .now() + delay) { entry.relay.send(entry.message) }
    }

    /// Once a second: ask devices for missing frames of stalled requests, and tidy up.
    private func startTick() {
        guard tick == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.onTick() }
        timer.resume()
        tick = timer
    }

    private func onTick() {
        for (pubkey, reassembler) in reassemblers {
            for stalled in reassembler.stalled(after: 2) {
                guard let relay = lastRelay[pubkey], let conversationKey = conversationKey(for: pubkey) else { continue }
                send([.resend(id: stalled.id, seqs: stalled.missing)], to: pubkey, conversationKey: conversationKey, relay: relay)
            }
        }
        let now = Date()
        requests = requests.filter { now.timeIntervalSince($0.value.at) < 600 }
        duplicateReplies = duplicateReplies.filter { now.timeIntervalSince($0.value) < 60 }
        unconfirmed = unconfirmed.filter { now.timeIntervalSince($0.value.sent) < 120 }
    }

    /// Console log for Nostr Connect (debug builds only).
    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[nostr-bridge] \(message())")
        #endif
    }

    // MARK: Bitcoin Core

    /// POSTs the JSON-RPC body to the local node and hands back Core's status and raw response.
    /// Only the node root and /wallet/<name> paths are allowed.
    private func forward(body: Data, path: String, timeout: Double, chain: String,
                         completion: @escaping (Int, Data, String?) -> Void) {
        guard path.isEmpty || (path.hasPrefix("/wallet/") && !path.dropFirst(8).contains("/") && !path.contains("..")) else {
            completion(0, Data(), "Path not allowed.")
            return
        }
        let user = UserDefaults.standard.string(forKey: "rpcuser") ?? "FullyNoded-Server"
        DataManager.retrieve(entityName: .rpcCreds) { creds in
            guard let encrypted = creds?["password"] as? Data,
                  let decrypted = Crypto.decrypt(encrypted),
                  let password = String(data: decrypted, encoding: .utf8),
                  let url = URL(string: "http://127.0.0.1:\(SPChain.port(for: chain))\(path)") else {
                completion(0, Data(), "Fully Noded Server has no RPC credentials for Bitcoin Core.")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = min(max(timeout, 10), 1_000)
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            request.httpBody = body
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let http = response as? HTTPURLResponse {
                    completion(http.statusCode, data ?? Data(), nil)
                } else {
                    completion(0, Data(), error?.localizedDescription ?? "No response from Bitcoin Core (\(chain)).")
                }
            }.resume()
        }
    }
}

extension NostrBridge: URLSessionWebSocketDelegate {
    /// Public relays: normal TLS validation. This Mac's relay: its pinned self-signed certificate.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let pin = queue.sync { localPin }
        let (disposition, credential) = NostrTLS.evaluate(challenge, pin: pin)
        completionHandler(disposition, credential)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            self?.relays.values.first { $0.task === webSocketTask }?.didOpen()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { [weak self] in
            self?.relays.values.first { $0.task === webSocketTask }?.didClose("Closed by the relay")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak self] in
            self?.relays.values.first { $0.task === task }?.didClose(error?.localizedDescription ?? "Disconnected")
        }
    }
}

/// One relay WebSocket. Callbacks run on the queue it was made with.
final class RelayConnection {
    let url: URL
    private(set) var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let queue: DispatchQueue
    private var pingTimer: DispatchSourceTimer?
    private var closed = false

    var onOpen: (() -> Void)?
    var onMessage: (([Any]) -> Void)?
    var onClose: ((String) -> Void)?

    init(url: URL, session: URLSession, queue: DispatchQueue) {
        self.url = url
        self.session = session
        self.queue = queue
    }

    func open() {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        self.task = task
        task.resume()
        receive()
    }

    func didOpen() {
        onOpen?()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.task?.sendPing { error in
                if let error = error { self?.queue.async { self?.didClose(error.localizedDescription) } }
            }
        }
        timer.resume()
        pingTimer = timer
    }

    func didClose(_ reason: String) {
        guard !closed else { return }
        closed = true
        pingTimer?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        onClose?(reason)
    }

    func close() {
        closed = true
        pingTimer?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
    }

    func send(_ message: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            if let error = error { self?.queue.async { self?.didClose(error.localizedDescription) } }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard !self.closed else { return }
                switch result {
                case .failure(let error):
                    self.didClose(error.localizedDescription)
                case .success(let message):
                    let data: Data?
                    switch message {
                    case .string(let s): data = s.data(using: .utf8)
                    case .data(let d): data = d
                    @unknown default: data = nil
                    }
                    if let data = data, let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                        self.onMessage?(array)
                    }
                    self.receive()
                }
            }
        }
    }
}
