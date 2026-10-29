//
//  TailscaleFunnel.swift
//  FullyNoded-Server
//
//  Tailscale Funnel for Nostr Connect: publishes this Mac's relay at a public
//  wss://<mac>.<tailnet>.ts.net address (a publicly trusted certificate, port 443), so Fully Noded
//  and Plasma reach it from anywhere with nothing on the phone: no Tailscale there, no port
//  forward, no ngrok. Driven with the `tailscale` CLI (`funnel --bg`, `funnel status --json`).
//
//  The first time, Tailscale may need HTTPS certificates and Funnel allowed for this Mac: the CLI
//  prints a login.tailscale.com link to approve that and waits, so it's shown as a button.
//
//  "On" isn't proof it works: Tailscale's ingress has been seen to stop forwarding to this Mac
//  (TLS dropped mid-handshake, no ingress node connected) while everything here looks fine, until
//  Funnel is turned off and on. So while it's on, the public address is checked the way a phone
//  away from home reaches it (public DNS, then TLS to the ingress), and Funnel is turned off and
//  on when it stops answering.
//

import Foundation
import AppKit
import Network

final class TailscaleFunnel: ObservableObject {
    static let shared = TailscaleFunnel()

    struct Status: Equatable {
        var installed = false
        /// Logged in and connected.
        var running = false
        /// This Mac's MagicDNS name ("mac.tail1234.ts.net").
        var host: String?
        /// What Funnel serves on port 443, if anything ("https+insecure://localhost:7777").
        var target: String?
        var funnelOn = false
    }

    @Published private(set) var status = Status()
    @Published private(set) var busy = false
    /// A Tailscale page to approve HTTPS / Funnel for this Mac, printed by the CLI while it waits.
    @Published private(set) var approvalURL: URL?
    @Published var error: String?

    /// Whether the public address actually answers from the internet.
    enum Reachability: Equatable {
        /// Funnel is off, or not checked yet.
        case unknown
        case checking
        case reachable(Date)
        case unreachable(String)
        /// Turning Funnel off and on because it stopped answering.
        case repairing
    }
    @Published private(set) var reachability: Reachability = .unknown
    /// When Funnel was last turned off and on automatically.
    @Published private(set) var lastRepair: Date?

    private var process: Process?
    private var monitor: Timer?
    private var probing = false
    /// Failed checks in a row (one failure could be a blip).
    private var failures = 0
    /// When Funnel was turned on here: public DNS can take a few minutes to find a new name.
    private var turnedOnAt: Date?

    static let checkInterval: TimeInterval = 180
    private static let failuresBeforeRepair = 2
    private static let minimumRepairInterval: TimeInterval = 600
    private static let startupGrace: TimeInterval = 180

    static var cli: String? {
        ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
         "/Applications/Tailscale.app/Contents/MacOS/Tailscale"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Funnel's target for the relay on `port` (it can't check the relay's self-signed certificate).
    static func target(port: UInt16, tls: Bool) -> String {
        tls ? "https+insecure://localhost:\(port)" : "http://localhost:\(port)"
    }

    /// Funnel is on and points at the relay on `port` with the right scheme.
    func isServingRelay(port: UInt16, tls: Bool) -> Bool {
        status.funnelOn && Self.matches(status.target, port: port, tls: tls)
    }

    /// The public relay address, while Funnel serves the relay.
    func relayURL(port: UInt16, tls: Bool) -> String? {
        guard isServingRelay(port: port, tls: tls), let host = status.host else { return nil }
        return "wss://\(host)"
    }

    private static func matches(_ target: String?, port: UInt16, tls: Bool) -> Bool {
        guard let target = target?.lowercased(), target.hasSuffix(":\(port)") || target.hasSuffix(":\(port)/") else { return false }
        return tls ? target.hasPrefix("https") : target.hasPrefix("http://") || !target.contains("://")
    }

    // MARK: - Status

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = Self.readStatus()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.status != status { self.status = status }
            }
        }
    }

    private static func readStatus() -> Status {
        var status = Status()
        guard let cli else { return status }
        status.installed = true
        guard let json = run(cli, ["status", "--json"]).output,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return status }
        status.running = object["BackendState"] as? String == "Running"
        if var name = (object["Self"] as? [String: Any])?["DNSName"] as? String, !name.isEmpty {
            if name.hasSuffix(".") { name.removeLast() }
            status.host = name
        }
        guard status.running, let host = status.host,
              let funnelJSON = run(cli, ["funnel", "status", "--json"]).output,
              let serve = try? JSONSerialization.jsonObject(with: Data(funnelJSON.utf8)) as? [String: Any] else { return status }
        let key = "\(host):443"
        let handlers = ((serve["Web"] as? [String: Any])?[key] as? [String: Any])?["Handlers"] as? [String: Any]
        status.target = (handlers?["/"] as? [String: Any])?["Proxy"] as? String
        status.funnelOn = (serve["AllowFunnel"] as? [String: Any])?[key] as? Bool == true
        return status
    }

    // MARK: - On / off

    /// Serves the relay on `port` publicly on 443. The first time, the CLI may print an approval
    /// link and wait up to a few minutes for it to be approved in the browser.
    func turnOn(port: UInt16, tls: Bool, completion: @escaping () -> Void) {
        turnOn(target: Self.target(port: port, tls: tls), completion: completion)
    }

    private func turnOn(target: String, completion: @escaping () -> Void) {
        guard let cli = Self.cli, !busy else { return }
        busy = true
        error = nil
        approvalURL = nil
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cli)
        task.arguments = ["funnel", "--bg", "--yes", target]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        var output = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            output += chunk
            if let match = chunk.range(of: #"https://login\.tailscale\.com/\S+"#, options: .regularExpression),
               let url = URL(string: String(chunk[match])) {
                DispatchQueue.main.async { self?.approvalURL = url }
            }
        }
        task.terminationHandler = { [weak self] task in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                self.busy = false
                self.approvalURL = nil
                if task.terminationStatus != 0, task.terminationReason != .uncaughtSignal {
                    let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.error = message.isEmpty ? "tailscale funnel exited with code \(task.terminationStatus)." : String(message.suffix(500))
                } else if task.terminationStatus == 0 {
                    self.turnedOnAt = Date()
                    self.failures = 0
                    self.reachability = .checking
                    self.scheduleCheck(after: 30)
                }
                self.refresh()
                completion()
            }
        }
        do {
            try task.run()
            process = task
        } catch {
            busy = false
            self.error = "Couldn't run tailscale: \(error.localizedDescription)"
            return
        }
        // Waiting for an approval that never comes: give up after 5 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self, let process = self.process, process === task, process.isRunning else { return }
            process.terminate()
            self.error = "Tailscale is still waiting for HTTPS / Funnel to be approved. Approve it, then turn Funnel on again."
        }
    }

    func cancel() {
        process?.terminate()
    }

    /// Stops serving on 443 (only that: other `tailscale serve` settings stay).
    func turnOff(completion: @escaping () -> Void) {
        guard let cli = Self.cli, !busy else { return }
        busy = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.run(cli, ["funnel", "--https=443", "--yes", "off"])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.reachability = .unknown
                self.failures = 0
                if result.status != 0 {
                    self.error = result.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Couldn't turn Funnel off."
                }
                self.refresh()
                completion()
            }
        }
    }

    // MARK: - Reachability

    /// Checks the public address every few minutes while Funnel is on (from launch).
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkReachability()
        }
        scheduleCheck(after: 5)
    }

    private func scheduleCheck(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.checkReachability() }
    }

    /// Reads Funnel's state, then connects to its public address from outside Tailscale. Two
    /// failures in a row turn Funnel off and on (at most every 10 minutes).
    func checkReachability() {
        guard !probing, !busy, Self.cli != nil else { return }
        probing = true
        if case .reachable = reachability {} else if reachability != .repairing { reachability = .checking }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = Self.readStatus()
            guard status.funnelOn, let host = status.host, let target = status.target else {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.probing = false
                    if self.status != status { self.status = status }
                    self.reachability = .unknown
                    self.failures = 0
                }
                return
            }
            let result = Self.probe(host: host)
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing = false
                if self.status != status { self.status = status }
                switch result {
                case .reachable:
                    self.failures = 0
                    self.reachability = .reachable(Date())
                case .noAddress(let reason):
                    // Repairing won't help DNS (a new name takes a few minutes to appear).
                    let settling = self.turnedOnAt.map { Date().timeIntervalSince($0) < Self.startupGrace } ?? false
                    self.reachability = settling ? .checking : .unreachable(reason)
                case .failed(let reason):
                    self.failures += 1
                    let settling = self.turnedOnAt.map { Date().timeIntervalSince($0) < Self.startupGrace } ?? false
                    let canRepair = self.lastRepair.map { Date().timeIntervalSince($0) >= Self.minimumRepairInterval } ?? true
                    if !settling, canRepair, self.failures >= Self.failuresBeforeRepair {
                        self.repair(target: target)
                    } else if let last = self.lastRepair, !canRepair {
                        // Only a failure that outlasts a restart is shown as a problem.
                        self.reachability = .unreachable("\(reason) Still failing after reconnecting at \(Self.time(last)).")
                    } else {
                        // A first failure (or one while DNS settles) may be a blip: check again soon.
                        self.reachability = .checking
                        self.scheduleCheck(after: 30)
                    }
                }
            }
        }
    }

    /// Turns Funnel off and on (what fixes a stuck ingress), then checks again.
    func repair() {
        guard let target = status.target else { return }
        repair(target: target)
    }

    private func repair(target: String) {
        guard let cli = Self.cli, !busy else { return }
        lastRepair = Date()
        reachability = .repairing
        busy = true
        error = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = Self.run(cli, ["funnel", "--https=443", "--yes", "off"])
            let on = Self.run(cli, ["funnel", "--bg", "--yes", target])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.failures = 0
                if on.status != 0 {
                    let message = on.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.error = "Couldn't turn Funnel back on: " + (message.isEmpty ? "exit code \(on.status)." : String(message.suffix(500)))
                    self.reachability = .unreachable("Funnel is off after a failed restart.")
                }
                self.refresh()
                self.scheduleCheck(after: 20)
            }
        }
    }

    private enum ProbeResult {
        case reachable
        case noAddress(String)
        case failed(String)
    }

    /// Resolves `host` with public DNS (this Mac's MagicDNS would give its tailnet address and skip
    /// the ingress), then completes a TLS handshake with each ingress address. TLS ends on this
    /// Mac, so a finished handshake means the ingress forwards here. Blocking: call off main.
    private static func probe(host: String) -> ProbeResult {
        let addresses = publicAddresses(of: host)
        guard !addresses.isEmpty else {
            return .noAddress("Public DNS has no address for \(host) yet.")
        }
        var failures: [String] = []
        for address in addresses {
            if let failure = handshake(address: address, host: host) {
                failures.append("\(address): \(failure)")
            } else {
                return .reachable
            }
        }
        return .failed("Tailscale's ingress isn't forwarding to this Mac (\(failures.joined(separator: "; "))).")
    }

    /// IPv4 addresses from DNS-over-HTTPS (Cloudflare, then Google).
    private static func publicAddresses(of host: String) -> [String] {
        let resolvers = ["https://1.1.1.1/dns-query", "https://dns.google/resolve"]
        for resolver in resolvers {
            guard var components = URLComponents(string: resolver) else { continue }
            components.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: "A")]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            let done = DispatchSemaphore(value: 0)
            var found: [String] = []
            URLSession.shared.dataTask(with: request) { data, _, _ in
                defer { done.signal() }
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let answers = json["Answer"] as? [[String: Any]] else { return }
                found = answers.compactMap { ($0["type"] as? Int) == 1 ? $0["data"] as? String : nil }
            }.resume()
            _ = done.wait(timeout: .now() + 12)
            if !found.isEmpty { return found }
        }
        return []
    }

    /// nil when a TLS handshake for `host` (normal certificate checks) completes with `address`.
    private static func handshake(address: String, host: String) -> String? {
        guard let ip = IPv4Address(address) else { return "not an IPv4 address" }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        let connection = NWConnection(host: .ipv4(ip), port: 443, using: NWParameters(tls: tls))
        let done = DispatchSemaphore(value: 0)
        var failure: String? = "timed out"
        var finished = false
        let queue = DispatchQueue(label: "funnel.probe")
        connection.stateUpdateHandler = { state in
            guard !finished else { return }
            switch state {
            case .ready:
                failure = nil
            case .failed(let error), .waiting(let error):
                failure = "\(error)"
            default:
                return
            }
            finished = true
            done.signal()
        }
        connection.start(queue: queue)
        _ = done.wait(timeout: .now() + 15)
        connection.cancel()
        return queue.sync { failure }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static let downloadURL = URL(string: "https://tailscale.com/download/mac")!

    func openTailscale() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
    }

    // MARK: - CLI

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, nil) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
