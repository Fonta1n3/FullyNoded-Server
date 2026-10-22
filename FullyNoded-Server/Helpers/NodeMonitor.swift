//
//  NodeMonitor.swift
//  FullyNoded-Server
//
//  Live state of the Bitcoin Core / Bitcoin Knots node for its page: whether it's running
//  (from RPC and, when RPC can't answer, from the process itself: see NodeProcess), sync
//  progress with an estimate of the time left, peers, mempool, uptime and the tail of
//  debug.log. Start, stop and the network switch live here too.
//
//  Polls getblockchaininfo every few seconds while the page is showing: fast during a start or
//  stop, slower otherwise (so a node started from the menu bar or Terminal still shows up).
//

import Foundation
import AppKit

final class NodeMonitor: ObservableObject {

    enum Kind {
        case core, knots

        var name: String { self == .core ? "Bitcoin Core" : "Bitcoin Knots" }
        var entity: Entity { self == .core ? .bitcoinEnv : .bitcoinKnotsEnv }
        var startScript: SCRIPT { self == .core ? .startBitcoin : .startKnots }
        var utilitiesWindow: String { self == .core ? "Utilities" : "Utilities-Knots" }
        var chains: [String] { self == .core ? ["main", "test", "testnet4", "signet", "regtest"] : ["main", "test", "signet", "regtest"] }
    }

    enum Phase: Equatable {
        case unknown
        case stopped
        /// With bitcoind's current init message (or a generic one).
        case starting(String)
        case running
        case stopping
        /// A start was asked for and bitcoind isn't running.
        case failed(String)

        var isTransitioning: Bool {
            switch self {
            case .starting, .stopping: return true
            default: return false
            }
        }
    }

    struct Peers: Equatable { let inbound: Int; let outbound: Int }
    struct Mempool: Equatable { let count: Int; let bytes: Int }

    static let core = NodeMonitor(kind: .core)
    static let knots = NodeMonitor(kind: .knots)

    let kind: Kind
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var chain: String
    @Published private(set) var version: String?
    @Published private(set) var info: BlockchainInfo?
    @Published private(set) var peers: Peers?
    @Published private(set) var mempool: Mempool?
    @Published private(set) var uptime: Int?
    @Published private(set) var subversion: String?
    /// Whether bitcoind can reach the onion network (it's using Tor).
    @Published private(set) var onionReachable: Bool?
    /// Other networks with a bitcoind running from this data folder.
    @Published private(set) var otherRunningChains: [String] = []
    @Published private(set) var logTail: [String] = []
    /// Seconds until fully verified, once enough progress has been seen to estimate it.
    @Published private(set) var timeLeft: TimeInterval?
    @Published private(set) var isRefreshing = false
    @Published var alert: String?

    private var env: [String: String] = [:]
    private var transition: NodeTransition?
    private var timer: Timer?
    private var visible = false
    /// Bumped on a network switch so replies for the old network are dropped.
    private var generation = 0
    private var inFlight = false
    private var progressSamples: [(date: Date, progress: Double)] = []
    /// The RPC problem last shown, so a poll doesn't show the same alert again.
    private var shownRPCProblem: String?

    private init(kind: Kind) {
        self.kind = kind
        // Core and Knots share the RPC port setting, so they share the network setting too.
        chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    }

    // MARK: - Page lifecycle

    func appear() {
        visible = true
        chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        DataManager.retrieve(entityName: kind.entity) { [weak self] env in
            DispatchQueue.main.async {
                guard let self else { return }
                if let env {
                    let version = env["version"] as? String ?? ""
                    self.version = version.isEmpty ? nil : version
                    self.env = [
                        "BINARY_NAME": env["binaryName"] as? String ?? "",
                        "VERSION": version,
                        "PREFIX": env["prefix"] as? String ?? "",
                        "DATADIR": Defaults.shared.bitcoinDataDir,
                        "CHAIN": self.chain
                    ]
                }
                self.refresh()
            }
        }
    }

    func disappear() {
        visible = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    func start() {
        guard !env.isEmpty else {
            alert = "\(kind.name) doesn't look installed: no install record was found."
            return
        }
        transition = .starting(Date())
        phase = .starting("Starting \(kind.name)…")
        progressSamples = []
        env["CHAIN"] = chain
        env["DATADIR"] = Defaults.shared.bitcoinDataDir
        ScriptUtil.runScript(script: kind.startScript, env: env, args: nil) { [weak self] _, _, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                // `bitcoind -daemon` reports launch errors (bad config, …) on stderr before it
                // forks. If a bitcoind is running anyway (it was already up), the poll shows that.
                if let errorMessage, !errorMessage.isEmpty, !self.processRunning {
                    self.transition = nil
                    self.phase = .failed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                    self.readLog()
                    return
                }
                self.refresh()
            }
        }
    }

    func stop() {
        transition = .stopping(Date())
        phase = .stopping
        BitcoinRPC.shared.command(method: "stop", params: [:]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if result == nil, let error, !Self.isUnreachable(error) {
                    self.transition = nil
                    self.alert = error
                }
                self.refresh()
            }
        }
    }

    func setChain(_ newChain: String) {
        guard newChain != chain else { return }
        chain = newChain
        generation += 1
        transition = nil
        info = nil
        clearLiveStats()
        phase = .unknown
        UserDefaults.standard.setValue(Self.rpcPort(chain: newChain), forKey: "port")
        UserDefaults.standard.setValue(newChain, forKey: "chain")
        env["CHAIN"] = newChain
        DataManager.update(keyToUpdate: "chain", newValue: newChain, entity: kind.entity) { [weak self] updated in
            DispatchQueue.main.async {
                if !updated { self?.alert = "There was an issue saving the network." }
            }
        }
        // Keeps JoinMarket on the node's network and RPC port.
        ConfigureJM.configureNetwork()
        refresh()
    }

    func openDebugLog() {
        let path = debugLogPath
        guard FileManager.default.fileExists(atPath: path) else {
            alert = "There's no debug.log for \(Self.networkName(chain)) yet:\n\(path)"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func showDataFolder() {
        let path = NodeProcess.networkDirectory(dataDir: Defaults.shared.bitcoinDataDir, chain: chain)
        let url = URL(fileURLWithPath: FileManager.default.fileExists(atPath: path) ? path : Defaults.shared.bitcoinDataDir)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Polling

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        isRefreshing = true
        let generation = self.generation
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.isRefreshing = false
                guard generation == self.generation else { self.refresh(); return }
                if let result = result as? [String: Any] {
                    self.handleInfo(BlockchainInfo(result))
                } else if let result = result as? String, result.isEmpty {
                    // HTTP 503: up, warming up.
                    self.handleBooting("Warming up…")
                } else {
                    self.handleError(error ?? "")
                }
                self.readLog()
                self.otherRunningChains = self.kind.chains.filter {
                    $0 != self.chain && NodeProcess.isRunning(dataDir: Defaults.shared.bitcoinDataDir, chain: $0)
                }
                self.schedule()
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard visible else { return }
        let interval: TimeInterval
        switch phase {
        case .starting, .stopping, .unknown: interval = 3
        case .running: interval = info?.initialblockdownload == true || (info?.verificationprogress ?? 1) < 0.9999 ? 5 : 10
        case .stopped, .failed: interval = 15
        }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while a menu is open
        self.timer = timer
    }

    private func handleInfo(_ info: BlockchainInfo) {
        // Right after `stop` the RPC may still answer once: keep saying "stopping".
        if case .stopping(let since) = transition, Date().timeIntervalSince(since) < 120 {
            phase = .stopping
            return
        }
        transition = nil
        shownRPCProblem = nil
        self.info = info
        phase = .running
        recordProgress(info.verificationprogress)
        fetchLiveStats()
    }

    private func handleBooting(_ message: String) {
        if case .stopping = transition {
            phase = .stopping
        } else {
            phase = .starting(message)
        }
    }

    private func handleError(_ error: String) {
        if error.contains("credentials are incorrect") || error.contains("No BitcoinRPCCreds")
            || error.contains("rpc password") || error.contains("Http error 403") {
            // Can't talk to it, but it may well be running.
            transition = nil
            info = nil
            phase = processRunning ? .running : .stopped
            if shownRPCProblem != error {
                shownRPCProblem = error
                alert = error
            }
            return
        }
        if !error.isEmpty && !Self.isUnreachable(error) {
            // RPC answered with an error: bitcoind is up but busy (loading the block index,
            // verifying blocks, shutting down, …).
            if error.contains("Shutdown in progress") || error.contains("Shutting down") {
                phase = .stopping
            } else {
                handleBooting(error)
            }
            return
        }
        // The RPC port refuses connections: off, or bitcoind still launching / shutting down.
        switch NodeProcess.interpretUnreachable(transition: transition, dataDir: Defaults.shared.bitcoinDataDir, chain: chain) {
        case .starting:
            if case .starting = phase { return }
            phase = .starting("Starting \(kind.name)…")
        case .stopping:
            phase = .stopping
        case .failedToStart:
            transition = nil
            phase = .failed("\(kind.name) didn't start. The end of its debug.log below usually says why.")
            stopped()
        case .stopped:
            transition = nil
            // Keep a "didn't start" on screen until the next start (or the node shows up).
            if case .failed = phase {} else { phase = .stopped }
            stopped()
        }
    }

    private func stopped() {
        info = nil
        clearLiveStats()
    }

    private func clearLiveStats() {
        peers = nil
        mempool = nil
        uptime = nil
        subversion = nil
        onionReachable = nil
        timeLeft = nil
        progressSamples = []
    }

    /// Peers, mempool and uptime: extras, so a failure (rpcwhitelist, …) just leaves them blank.
    private func fetchLiveStats() {
        let generation = self.generation
        BitcoinRPC.shared.command(method: "getnetworkinfo", params: [:]) { [weak self] result, _ in
            guard let result = result as? [String: Any] else { return }
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                let inbound = result["connections_in"] as? Int
                let outbound = result["connections_out"] as? Int
                if let inbound, let outbound {
                    self.peers = Peers(inbound: inbound, outbound: outbound)
                } else if let total = result["connections"] as? Int {
                    self.peers = Peers(inbound: 0, outbound: total)
                }
                self.subversion = (result["subversion"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let networks = result["networks"] as? [[String: Any]] ?? []
                self.onionReachable = networks.first { $0["name"] as? String == "onion" }?["reachable"] as? Bool
            }
        }
        BitcoinRPC.shared.command(method: "getmempoolinfo", params: [:]) { [weak self] result, _ in
            guard let result = result as? [String: Any] else { return }
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.mempool = Mempool(count: result["size"] as? Int ?? 0, bytes: result["bytes"] as? Int ?? 0)
            }
        }
        BitcoinRPC.shared.command(method: "uptime", params: [:]) { [weak self] result, _ in
            guard let seconds = result as? Int else { return }
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.uptime = seconds
            }
        }
    }

    /// Estimates the time left from the verification progress over the last few minutes.
    private func recordProgress(_ progress: Double) {
        let now = Date()
        guard progress < 0.9999 else {
            progressSamples = []
            timeLeft = nil
            return
        }
        progressSamples.append((now, progress))
        progressSamples.removeAll { now.timeIntervalSince($0.date) > 600 }
        guard let first = progressSamples.first, now.timeIntervalSince(first.date) >= 30,
              progress > first.progress else {
            timeLeft = nil
            return
        }
        let rate = (progress - first.progress) / now.timeIntervalSince(first.date)
        timeLeft = (1 - progress) / rate
    }

    // MARK: - debug.log

    var debugLogPath: String {
        NodeProcess.networkDirectory(dataDir: Defaults.shared.bitcoinDataDir, chain: chain) + "/debug.log"
    }

    /// The last lines of debug.log (only its end is read: it can be gigabytes).
    private func readLog() {
        let path = debugLogPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var lines: [String] = []
            if let handle = FileHandle(forReadingAtPath: path) {
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                let chunk: UInt64 = 16 * 1024
                try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
                if let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    lines = text.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if size > chunk { lines = Array(lines.dropFirst()) } // first line is likely cut
                    lines = Array(lines.suffix(8))
                }
            }
            DispatchQueue.main.async {
                guard let self, path == self.debugLogPath else { return }
                if self.logTail != lines { self.logTail = lines }
            }
        }
    }

    // MARK: - Helpers

    private var processRunning: Bool {
        NodeProcess.isRunning(dataDir: Defaults.shared.bitcoinDataDir, chain: chain)
    }

    /// URLSession errors that mean nothing is listening (yet) on the RPC port.
    static func isUnreachable(_ error: String) -> Bool {
        let lower = error.lowercased()
        return ["could not connect to the server", "network connection was lost", "timed out",
                "connection refused", "not connected to the internet"].contains { lower.contains($0) }
    }

    static func rpcPort(chain: String) -> String {
        switch chain {
        case "signet": return "38332"
        case "regtest": return "18443"
        case "test": return "18332"
        case "testnet4": return "48332"
        default: return "8332"
        }
    }

    static func networkName(_ chain: String) -> String {
        switch chain {
        case "main": return "Mainnet"
        case "test": return "Testnet3"
        case "testnet4": return "Testnet4"
        case "signet": return "Signet"
        case "regtest": return "Regtest"
        default: return chain
        }
    }
}
