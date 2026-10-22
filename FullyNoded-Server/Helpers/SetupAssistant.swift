//
//  SetupAssistant.swift
//  FullyNoded-Server
//
//  State for the Setup Assistant (SetupAssistantView): checks this Mac, applies the node
//  settings the user picks, starts the node and follows its sync.
//
//  Settings go where the rest of the app reads them:
//  • "useKnots", "chain", "port", "dataDir", "prune" (MiB, 0 = off), "txindex" in UserDefaults
//  • the installed implementation's env (chain) in Core Data
//

import Foundation
import AppKit

extension Notification.Name {
    /// Opens the Setup Assistant (Help page, app menu).
    static let showSetupAssistant = Notification.Name("FNS.showSetupAssistant")
}

final class SetupAssistant: ObservableObject {

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, check, configure, install, start, connect

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .check: return "Check"
            case .configure: return "Configure"
            case .install: return "Install"
            case .start: return "Start"
            case .connect: return "Connect"
            }
        }
    }

    enum Storage: String { case pruned, full }

    /// Whether the assistant has been finished or dismissed (it opens by itself until then).
    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: "setupAssistantComplete") }
        set { UserDefaults.standard.set(newValue, forKey: "setupAssistantComplete") }
    }

    @Published var step: Step = .welcome

    // MARK: Check
    @Published private(set) var freeBytes: Int64?
    @Published private(set) var memoryBytes = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var hasCommandLineTools: Bool?
    @Published private(set) var hasHomebrew: Bool?
    @Published private(set) var torState: TorClient.TorState = TorClient.sharedInstance.state
    /// bitcoin.conf already in the data directory (its settings are kept).
    @Published private(set) var existingConf: (prune: Int?, txindex: Int?)?

    // MARK: Configure
    @Published var implementation: NodeImplementation = .selected
    @Published var chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @Published var storage: Storage = Defaults.shared.prune == 0 ? .full : .pruned
    /// Prune target in GB (bitcoind's minimum is 550 MiB). 50 GB unless one was chosen before.
    @Published var pruneGB: Double = UserDefaults.standard.object(forKey: "prune") == nil
        ? 50
        : max(1, (Double(Defaults.shared.prune) / 953.674).rounded())
    @Published private(set) var dataDir = Defaults.shared.bitcoinDataDir

    // MARK: Install / start
    let installer = NodeInstaller()
    /// The chosen implementation's install, if any.
    @Published private(set) var installedEnv: BitcoinEnvValues?
    @Published private(set) var nodeStatus: NodeStatus = .unknown
    @Published private(set) var blockchainInfo: BlockchainInfo?

    enum NodeStatus: Equatable {
        case unknown, stopped, starting(String), running
        case failed(String)
    }

    private var torTimer: Timer?
    private var nodeTimer: Timer?

    deinit {
        torTimer?.invalidate()
        nodeTimer?.invalidate()
    }

    // MARK: - Check

    func runChecks() {
        refreshFreeSpace()
        readExistingConf()
        refreshInstall()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // xcode-select -p exits 0 only when a developer directory (the Command Line Tools
            // or Xcode) is installed; the xcode-select binary itself is always there.
            let tools = Self.run("/usr/bin/xcode-select", ["-p"]) == 0
            let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains { FileManager.default.isExecutableFile(atPath: $0) }
            DispatchQueue.main.async {
                self?.hasCommandLineTools = tools
                self?.hasHomebrew = brew
            }
        }

        torTimer?.invalidate()
        torState = TorClient.sharedInstance.state
        torTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.torState = TorClient.sharedInstance.state
        }
    }

    func installCommandLineTools() {
        ScriptUtil.runScript(script: .installXcode, env: nil, args: nil) { _, _, _ in }
    }

    func installHomebrew() {
        ScriptUtil.runScript(script: .installHomebrew, env: nil, args: nil) { _, _, _ in }
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    /// Free space on the data directory's volume (the folder may not exist yet).
    private func refreshFreeSpace() {
        var url = URL(fileURLWithPath: dataDir)
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeBytes = values?.volumeAvailableCapacityForImportantUsage
    }

    private func readExistingConf() {
        BitcoinConf.getBitcoinConf { [weak self] conf, _ in
            guard let conf else {
                DispatchQueue.main.async { self?.existingConf = nil }
                return
            }
            func value(_ key: String) -> Int? {
                conf.first { $0.hasPrefix("\(key)=") }.flatMap { Int($0.dropFirst(key.count + 1)) }
            }
            let found = (prune: value("prune"), txindex: value("txindex"))
            DispatchQueue.main.async {
                self?.existingConf = found
                if let prune = found.prune {
                    self?.storage = prune == 0 ? .full : .pruned
                    if prune > 1 { self?.pruneGB = max(1, (Double(prune) / 953.674).rounded()) }
                }
            }
        }
    }

    // MARK: - Configure

    /// Rough size of each network's chain, for the storage hint.
    static func fullSizeGB(chain: String) -> Int {
        switch chain {
        case "main": return 750
        case "test": return 200
        case "testnet4": return 20
        case "signet": return 25
        default: return 1
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

    static func networkDetail(_ chain: String) -> String {
        switch chain {
        case "main": return "Real bitcoin. Use this for your own money."
        case "test": return "The long-running public test network. Coins have no value."
        case "testnet4": return "The newer public test network. Coins have no value."
        case "signet": return "A stable test network with predictable blocks. Good for trying things out."
        case "regtest": return "A private chain on this Mac only, for development."
        default: return ""
        }
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

    /// Bytes the chosen settings need on disk (block data plus ~10 GB for the chainstate).
    var requiredBytes: Int64 {
        let gb: Double = storage == .full ? Double(Self.fullSizeGB(chain: chain)) : pruneGB + 10
        return Int64(gb * 1_000_000_000)
    }

    var pruneMiB: Int { max(550, Int(pruneGB * 953.674)) }

    func chooseDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Bitcoin keeps the blockchain, e.g. an external drive."
        panel.directoryURL = URL(fileURLWithPath: dataDir)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dataDir = url.path
        refreshFreeSpace()
        readExistingConf()
    }

    /// Writes the choices where the app reads them. Prune / txindex only matter for a new
    /// bitcoin.conf; an existing one keeps its own.
    func applyConfiguration() {
        let ud = UserDefaults.standard
        ud.set(implementation == .knots, forKey: "useKnots")
        ud.set(chain, forKey: "chain")
        ud.set(Self.rpcPort(chain: chain), forKey: "port")
        ud.set(dataDir, forKey: "dataDir")
        if existingConf == nil {
            ud.set(storage == .full ? 0 : pruneMiB, forKey: "prune")
            ud.set(storage == .full ? 1 : 0, forKey: "txindex")
        }
        refreshInstall {
            // Already installed: point it at the chosen network.
            guard $0 != nil else { return }
            DataManager.update(keyToUpdate: "chain", newValue: self.chain, entity: self.implementation.entity) { _ in }
            DataManager.update(keyToUpdate: "dataDir", newValue: self.dataDir, entity: self.implementation.entity) { _ in }
            self.refreshInstall()
        }
    }

    func refreshInstall(completion: ((BitcoinEnvValues?) -> Void)? = nil) {
        implementation.installedEnv { [weak self] env in
            DispatchQueue.main.async {
                self?.installedEnv = env
                completion?(env)
            }
        }
    }

    // MARK: - Start

    /// When Start was tapped: until bitcoind is up, a refused RPC means "starting", not "off".
    private var startRequested: Date?

    func startNode() {
        guard let env = installedEnv else { return }
        nodeStatus = .starting("Starting \(implementation.name)…")
        startRequested = Date()
        let scriptEnv = [
            "BINARY_NAME": env.binaryName,
            "VERSION": env.version,
            "PREFIX": env.prefix,
            "DATADIR": Defaults.shared.bitcoinDataDir,
            "CHAIN": chain
        ]
        ScriptUtil.runScript(script: implementation.startScript, env: scriptEnv, args: nil) { [weak self] _, _, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                // Launch errors are on stderr; ignore them if a bitcoind is running anyway.
                if let errorMessage, !errorMessage.isEmpty,
                   !NodeProcess.isRunning(dataDir: Defaults.shared.bitcoinDataDir, chain: self.chain) {
                    self.startRequested = nil
                    self.nodeStatus = .failed(errorMessage)
                    return
                }
                self.followNode()
            }
        }
    }

    /// Polls getblockchaininfo while the Start step is showing.
    func followNode() {
        nodeTimer?.invalidate()
        pollNode()
        nodeTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.pollNode()
        }
    }

    func stopFollowingNode() {
        nodeTimer?.invalidate()
        nodeTimer = nil
    }

    private func pollNode() {
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result = result as? [String: Any] {
                    self.blockchainInfo = BlockchainInfo(result)
                    self.startRequested = nil
                    self.nodeStatus = .running
                    return
                }
                // HTTP 503 (BitcoinRPC returns ""): up, but still warming up.
                if let result = result as? String, result.isEmpty {
                    self.nodeStatus = .starting("Warming up…")
                    return
                }
                let error = error ?? ""
                if error.isEmpty || error.contains("Could not connect to the server") {
                    // Not up (yet): the RPC port also refuses while bitcoind launches, so ask the OS.
                    switch NodeProcess.interpretUnreachable(transition: self.startRequested.map { .starting($0) },
                                                           dataDir: Defaults.shared.bitcoinDataDir, chain: self.chain) {
                    case .starting, .stopping:
                        if case .starting = self.nodeStatus { return }
                        self.nodeStatus = .starting("Starting \(self.implementation.name)…")
                    case .failedToStart:
                        self.startRequested = nil
                        self.nodeStatus = .failed("\(self.implementation.name) didn't start. Its debug.log (Utilities → debug.log) says why.")
                    case .stopped:
                        self.nodeStatus = .stopped
                    }
                } else if error.contains("credentials are incorrect") || error.contains("No BitcoinRPCCreds") {
                    self.nodeStatus = .failed(error)
                } else {
                    // Loading block index, verifying blocks, …: bitcoind is starting.
                    self.nodeStatus = .starting(error)
                }
            }
        }
    }

    // MARK: - Finish

    func finish() {
        Self.isComplete = true
        torTimer?.invalidate()
        stopFollowingNode()
    }
}
