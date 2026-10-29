//
//  LightningNode.swift
//  FullyNoded-Server
//
//  Core Lightning (lightningd) next to this Mac's bitcoind: install and update with Homebrew,
//  start and stop, live status over its RPC socket, funds, and pairing wallets: Plasma over
//  Nostr Connect (wss:// relays to FN-Server's bridge, which calls clnrest with the pairing's
//  rune), others over CLNRest on an onion address.
//
//  • Binaries: Homebrew's `opt/core-lightning` link, which survives upgrades (the old setup
//    pointed at a versioned Cellar folder and broke on every `brew upgrade`).
//  • Config: FN-Server writes ~/.lightning/fns-server.conf on every start and passes it with
//    `--conf`, so lightningd ignores ~/.lightning/config (left as it is). The user's own options
//    go in ~/.lightning/<network>/config, which lightningd still reads.
//  • Node data (hsm_secret, the channel database) in ~/.lightning/<network>/ is never written
//    or deleted here: an existing node is simply started.
//  • bitcoind: through FN-Server's own bitcoin-cli with the node's data folder, so it
//    authenticates with bitcoind's cookie (no RPC password in any file).
//  • Network: follows the Bitcoin node's.
//

import Foundation
import AppKit

final class LightningNode: ObservableObject {

    enum Install: Equatable {
        case checking
        case needsHomebrew
        case notInstalled
        /// Homebrew is running in Terminal.
        case installing
        case failed(String)
        case installed
    }

    enum Phase: Equatable {
        case unknown
        case stopped
        case starting(String)
        case running
        case stopping
        case failed(String)
        /// This version won't upgrade the node's database by itself (it isn't a final release):
        /// with the message, e.g. "from version 256 to 261 in non-final version 24.11.1".
        case needsDatabaseUpgrade(String)

        var isTransitioning: Bool {
            switch self {
            case .starting, .stopping, .unknown: return true
            default: return false
            }
        }
    }

    struct Info: Equatable {
        let id: String
        let alias: String
        let color: String
        let peers: Int
        let activeChannels: Int
        let pendingChannels: Int
        let inactiveChannels: Int
        let blockheight: Int
        let version: String
        let warnings: [String]
        /// Where lightningd listens for peers (and Plasma), e.g. "0.0.0.0:9735".
        let bindings: [String]

        init(_ d: [String: Any]) {
            id = d["id"] as? String ?? ""
            alias = d["alias"] as? String ?? ""
            color = d["color"] as? String ?? ""
            peers = d["num_peers"] as? Int ?? 0
            activeChannels = d["num_active_channels"] as? Int ?? 0
            pendingChannels = d["num_pending_channels"] as? Int ?? 0
            inactiveChannels = d["num_inactive_channels"] as? Int ?? 0
            blockheight = d["blockheight"] as? Int ?? 0
            version = d["version"] as? String ?? ""
            warnings = ["warning_bitcoind_sync", "warning_lightningd_sync"].compactMap { d[$0] as? String }
            bindings = (d["binding"] as? [[String: Any]] ?? []).compactMap { binding in
                guard let address = binding["address"] as? String else { return nil }
                return binding["port"].map { "\(address):\($0)" } ?? address
            }
        }
    }

    struct Funds: Equatable {
        var onchainConfirmed = 0
        var onchainUnconfirmed = 0
        /// Our side of normal channels.
        var inChannels = 0
        var channelCount = 0
    }

    struct Connection: Equatable {
        let host: String
        let port: Int
        let rune: String
        let readOnly: Bool
        var url: String { "clnrest://\(host):\(port)?rune=\(rune)" }
    }

    static let plasmaAppStore = URL(string: "https://apps.apple.com/us/app/plasma-core-lightning-wallet/id6468914352")!
    static let shared = LightningNode()
    /// Lightning peer port per network: Core Lightning's own defaults, so nodes for different
    /// networks can run side by side (one fixed port made the second one fail to bind).
    static func peerPort(network: String) -> Int {
        switch network {
        case "testnet": return 19735
        case "testnet4": return 49735
        case "signet": return 39735
        case "regtest": return 19846
        default: return 9735
        }
    }

    /// clnrest port per network. The Tor onion for Core Lightning forwards all of them.
    static func restPort(network: String) -> Int {
        switch network {
        case "testnet": return 18766
        case "testnet4": return 18767
        case "signet": return 18768
        case "regtest": return 18769
        default: return 18765
        }
    }

    /// cln-grpc port per network (it listens on 9736 by default, on every network, and is an
    /// "important" plugin: a second node exits when it can't bind it).
    static func grpcPort(network: String) -> Int {
        switch network {
        case "testnet": return 19736
        case "testnet4": return 49736
        case "signet": return 39736
        case "regtest": return 19847
        default: return 9736
        }
    }

    var peerPort: Int { Self.peerPort(network: network) }
    var restPort: Int { Self.restPort(network: network) }

    @Published private(set) var install: Install = .checking
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var version: String?
    /// Homebrew's current version, when newer than the installed one.
    @Published private(set) var updateAvailable: String?
    @Published private(set) var info: Info?
    @Published private(set) var funds: Funds?
    @Published private(set) var restListening: Bool?
    /// Why the REST server isn't configured, when it isn't.
    @Published private(set) var restUnavailable: String?
    @Published private(set) var logTail: [String] = []
    @Published private(set) var otherRunningNetworks: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var connection: Connection?
    /// A Plasma pairing over Nostr Connect, shown once: (nostr+plasma:// link, read-only).
    @Published private(set) var plasmaNostr: (link: String, readOnly: Bool)?
    /// The Bitcoin node's pruning, as it affects Core Lightning.
    struct Pruning: Equatable {
        /// Lowest block bitcoind still has.
        let pruneHeight: Int
        let tipHeight: Int
        /// lightningd is behind blocks bitcoind no longer has: it can't catch up.
        let stuckAt: Int?
        /// About how long lightningd can be off before it can't catch up (10-minute blocks).
        var window: TimeInterval { TimeInterval(max(0, tipHeight - pruneHeight)) * 600 }
    }

    /// nil: the Bitcoin node isn't pruned (or isn't answering).
    @Published private(set) var pruning: Pruning?

    /// The macOS firewall is on and doesn't allow incoming connections to this version's
    /// lightning_connectd (the process that accepts Plasma and peers). Homebrew's binaries are
    /// only ad-hoc signed, so they're never allowed automatically, and every upgrade moves them
    /// to a new Cellar path that needs its own rule. The value is that path.
    @Published private(set) var firewallBlockedPath: String?

    /// Run in Terminal (it asks for the user's password): allows lightning_connectd in.
    var firewallCommand: String? {
        firewallBlockedPath.map {
            "sudo \(Self.socketFilter) --add \"\($0)\" && sudo \(Self.socketFilter) --unblockapp \"\($0)\""
        }
    }

    private static let socketFilter = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    /// The installed lightning_connectd, with symlinks resolved (the firewall keys rules by it).
    static var connectdPath: String? {
        guard let prefix else { return nil }
        let path = (prefix + "/libexec/c-lightning/lightning_connectd" as NSString).resolvingSymlinksInPath
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func checkFirewall() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var blocked: String?
            if let path = Self.connectdPath,
               let state = Self.run(Self.socketFilter, ["--getglobalstate"]), state.contains("enabled") {
                let apps = Self.run(Self.socketFilter, ["--listapps"]) ?? ""
                // "N : <path>" then "(Allow incoming connections)" on the next line.
                let lines = apps.components(separatedBy: "\n")
                let allowed = lines.indices.contains { i in
                    lines[i].trimmingCharacters(in: .whitespaces).hasSuffix(path)
                        && i + 1 < lines.count && lines[i + 1].contains("Allow incoming")
                }
                if !allowed { blocked = path }
            }
            DispatchQueue.main.async {
                if self?.firewallBlockedPath != blocked { self?.firewallBlockedPath = blocked }
            }
        }
    }

    func openFirewallSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall") {
            NSWorkspace.shared.open(url)
        }
    }

    @Published private(set) var depositAddress: String?
    @Published var alert: String?
    /// Connect to Lightning peers only through Tor (FN-Server's SOCKS proxy).
    @Published var peersOverTor: Bool {
        didSet { UserDefaults.standard.set(peersOverTor, forKey: Self.torPeersKey) }
    }
    /// Accept Lightning peer connections on all of this Mac's addresses (local network, VPN, a
    /// forwarded port). Off: this Mac only. Plasma doesn't need it (it uses Nostr Connect).
    @Published var acceptPeersOnNetwork: Bool {
        didSet { UserDefaults.standard.set(acceptPeersOnNetwork, forKey: Self.peersOnNetworkKey) }
    }

    private static let torPeersKey = "clnPeersOverTor"
    private static let peersOnNetworkKey = "clnAcceptPeersOnNetwork"
    private var timer: Timer?
    private var visible = false
    private var inFlight = false
    private var transitionStarted: Date?
    private var allowDatabaseUpgrade = false
    /// `lightningd --daemon` returned: from then on, no process means it exited.
    private var launchReturned = false
    private var generation = 0
    private static let startGrace: TimeInterval = 90

    private init() {
        peersOverTor = UserDefaults.standard.object(forKey: Self.torPeersKey) as? Bool ?? true
        acceptPeersOnNetwork = UserDefaults.standard.bool(forKey: Self.peersOnNetworkKey)
    }

    // MARK: - Paths

    static var lightningDir: String { NSHomeDirectory() + "/.lightning" }
    static var confPath: String { lightningDir + "/fns-server.conf" }
    static var installStatusPath: String { NSHomeDirectory() + "/.fullynoded/lightning-install.status" }

    /// Homebrew's stable link for core-lightning (Apple silicon, then Intel).
    static var prefix: String? {
        ["/opt/homebrew/opt/core-lightning", "/usr/local/opt/core-lightning"].first {
            FileManager.default.isExecutableFile(atPath: $0 + "/bin/lightningd")
        }
    }

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The chain's name in lightningd.
    static func network(chain: String) -> String {
        switch chain {
        case "main": return "bitcoin"
        case "test": return "testnet"
        default: return chain // testnet4, signet, regtest
        }
    }

    var chain: String { UserDefaults.standard.string(forKey: "chain") ?? "main" }
    var network: String { Self.network(chain: chain) }
    var networkDir: String { Self.lightningDir + "/" + network }
    var socketPath: String { networkDir + "/lightning-rpc" }
    var logPath: String { networkDir + "/fns-lightningd.log" }
    var hsmSecretPath: String { networkDir + "/hsm_secret" }
    var hasExistingNode: Bool { FileManager.default.fileExists(atPath: hsmSecretPath) }

    static func pidFile(network: String) -> String { lightningDir + "/lightningd-\(network).pid" }

    static func isRunning(network: String) -> Bool {
        NodeProcess.runningPID(pidFile: pidFile(network: network), executable: "lightningd") != nil
    }

    var processRunning: Bool { Self.isRunning(network: network) }

    // MARK: - Lifecycle

    func appear() {
        visible = true
        checkInstall()
        checkFirewall()
    }

    func disappear() {
        visible = false
        timer?.invalidate()
        timer = nil
    }

    /// Install state, then status.
    func checkInstall() {
        if Self.prefix != nil {
            if install == .installing { clearInstallStatus() }
            install = .installed
            readVersion()
            refresh()
            return
        }
        if install == .installing {
            // Homebrew's still going in Terminal: its status file says when it's done.
            if let status = Self.readInstallStatus(), status.hasPrefix("failed") {
                install = .failed(String(status.dropFirst("failed".count)).trimmingCharacters(in: .whitespaces))
                clearInstallStatus()
            }
            schedule(after: 3) { [weak self] in self?.checkInstall() }
            return
        }
        install = Self.brewPath == nil ? .needsHomebrew : .notInstalled
        phase = .stopped
    }

    // MARK: - Install / update

    func installHomebrew() {
        ScriptUtil.runScript(script: .installHomebrew, env: nil, args: nil) { _, _, _ in }
        alert = "Homebrew's installer opened in Terminal. Come back here once it's finished."
    }

    /// Installs (or updates) with Homebrew in a Terminal window.
    func installOrUpdate() {
        if Self.prefix != nil && (processRunning || phase == .running) {
            alert = "Stop Core Lightning before updating it: Homebrew replaces the files the running node uses."
            return
        }
        clearInstallStatus()
        let updating = Self.prefix != nil
        install = .installing
        ScriptUtil.runScript(script: .launchLightningInstall, env: nil, args: nil) { [weak self] _, _, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMessage, !errorMessage.isEmpty {
                    self.install = .failed(errorMessage)
                    return
                }
                if updating {
                    self.waitForUpdate()
                } else {
                    self.checkInstall()
                }
            }
        }
    }

    /// While updating, lightningd stays installed: wait for the script's status instead.
    private func waitForUpdate() {
        guard let status = Self.readInstallStatus(), status != "running" else {
            schedule(after: 3) { [weak self] in self?.waitForUpdate() }
            return
        }
        clearInstallStatus()
        if status.hasPrefix("failed") {
            install = .failed(String(status.dropFirst("failed".count)).trimmingCharacters(in: .whitespaces))
        } else {
            install = .installed
            updateAvailable = nil
            readVersion()
            refresh()
        }
    }

    private static func readInstallStatus() -> String? {
        (try? String(contentsOfFile: installStatusPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearInstallStatus() {
        try? FileManager.default.removeItem(atPath: Self.installStatusPath)
    }

    private func readVersion() {
        guard let prefix = Self.prefix else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = Self.run(prefix + "/bin/lightningd", ["--version"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            var latest: String?
            if let brew = Self.brewPath, let json = Self.run(brew, ["info", "--json=v2", "core-lightning"]),
               let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let formula = (object["formulae"] as? [[String: Any]])?.first,
               let versions = formula["versions"] as? [String: Any] {
                latest = versions["stable"] as? String
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.version = installed.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
                if let latest, let installed = self.version, Self.isNewer(latest, than: installed) {
                    self.updateAvailable = latest
                } else {
                    self.updateAvailable = nil
                }
            }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - Start / stop

    /// `upgradeDatabase`: pass `--database-upgrade=true` (after `backupDatabase()`), for a
    /// version that won't upgrade an older node's database by itself.
    func start(upgradeDatabase: Bool = false) {
        guard let prefix = Self.prefix else { return }
        allowDatabaseUpgrade = upgradeDatabase
        launchReturned = false
        phase = .starting("Checking your Bitcoin node…")
        transitionStarted = Date()
        hideConnection()
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if result is [String: Any] || (result as? String)?.isEmpty == true {
                    self.launch(prefix: prefix)
                } else if let error, NodeMonitor.isUnreachable(error) {
                    self.abortStart("Your Bitcoin node isn't running. Start it first: Core Lightning needs it.")
                } else if let error, error.contains("credentials") || error.contains("No BitcoinRPCCreds") {
                    self.abortStart(error)
                } else {
                    self.launch(prefix: prefix) // busy starting up: lightningd waits for it
                }
            }
        }
    }

    private func abortStart(_ message: String) {
        phase = .stopped
        transitionStarted = nil
        alert = message
    }

    private func launch(prefix: String) {
        phase = .starting("Starting lightningd…")
        bitcoinCliPath { [weak self] bitcoinCli in
            guard let self else { return }
            guard let bitcoinCli else {
                self.abortStart("Couldn't find bitcoin-cli for your node (FN-Server's install folder or Homebrew's).")
                return
            }
            self.runLightningd(prefix: prefix, bitcoinCli: bitcoinCli, withRest: Self.hasPlugin("clnrest", prefix: prefix))
        }
    }

    private func runLightningd(prefix: String, bitcoinCli: String, withRest: Bool) {
        restUnavailable = withRest ? nil : "This Core Lightning's REST plugin isn't the built-in one (older versions need extra Python packages). Update Core Lightning to connect wallets."
        do {
            try self.writeConfig(prefix: prefix, bitcoinCli: bitcoinCli, withRest: withRest)
        } catch {
            self.abortStart("Couldn't write \(Self.confPath): \(error.localizedDescription)")
            return
        }
        let arguments = [
            "--conf=\(Self.confPath)",
            "--lightning-dir=\(Self.lightningDir)",
            "--network=\(self.network)",
            "--log-file=\(self.logPath)",
            "--daemon"
        ] + (allowDatabaseUpgrade ? ["--database-upgrade=true"] : [])
        #if DEBUG
        print("[cln] \(prefix)/bin/lightningd \(arguments.joined(separator: " "))")
        #endif
        let generation = self.generation
        DispatchQueue.global(qos: .userInitiated).async {
            // With --daemon, lightningd forks once it's set up; errors before that (bad
            // option, can't reach bitcoind, …) come back here on stderr.
            let result = Self.runWithStatus(prefix + "/bin/lightningd", arguments, timeout: 120)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                if result.status != 0 && !self.processRunning {
                    let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if reason.contains("Refusing to irreversibly upgrade db") {
                        let detail = reason.range(of: "from version").map { String(reason[$0.lowerBound...]) } ?? reason
                        self.phase = .needsDatabaseUpgrade(detail.components(separatedBy: " (use")[0])
                        self.transitionStarted = nil
                        return
                    }
                    // The REST plugin disabled itself (missing dependency), so its options are
                    // unknown: start without them rather than not at all.
                    if withRest && reason.contains("clnrest") && reason.contains("unknown option") {
                        self.runLightningd(prefix: prefix, bitcoinCli: bitcoinCli, withRest: false)
                        return
                    }
                    self.phase = .failed(reason.isEmpty ? "lightningd exited with code \(result.status). Its log below may say why." : String(reason.suffix(600)))
                    self.transitionStarted = nil
                    self.readLog()
                    return
                }
                self.launchReturned = true
                self.refresh()
            }
        }
    }

    /// The last **BROKEN** line of the log since `since` (why lightningd exited), if any.
    private func brokenLogLine(since: Date?) -> String? {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").filter { line in
            // The cause, not the crash report that follows it.
            guard line.contains("**BROKEN**"), !line.contains("FATAL SIGNAL"), !line.contains("backtrace") else { return false }
            guard let since, let stamp = line.split(separator: " ").first, let date = formatter.date(from: String(stamp)) else { return true }
            return date >= since.addingTimeInterval(-2)
        }
        guard let line = lines.last else { return nil }
        // "2026-…Z **BROKEN** connectd: Failed to bind …" → "connectd: Failed to bind …"
        return line.components(separatedBy: "**BROKEN** ").last?.trimmingCharacters(in: .whitespaces)
    }

    /// A friendlier reason for the failures FN-Server can recognize.
    private func explain(_ broken: String) -> String {
        if broken.contains("Failed to bind") && broken.contains("Address already in use") {
            let others = otherRunningNetworks.isEmpty ? "" : " (Core Lightning on \(otherRunningNetworks.joined(separator: ", ")) is running)"
            return "Port \(peerPort) is already in use by another program\(others). lightningd said: \(broken)"
        }
        return broken
    }

    /// Copies the node's databases to <network>/fns-backups/<date>/ before an irreversible upgrade.
    /// Only while lightningd is stopped, so the copy is consistent. Returns the folder, or why not.
    func backupDatabase() -> Result<String, BackupError> {
        guard !processRunning else { return .failure(BackupError(message: "Stop Core Lightning first.")) }
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = networkDir + "/fns-backups/" + stamp
        let files = ["lightningd.sqlite3", "lightningd.sqlite3-wal", "lightningd.sqlite3-shm",
                     "accounts.sqlite3", "emergency.recover"].filter { fm.fileExists(atPath: networkDir + "/" + $0) }
        guard !files.isEmpty else { return .success(folder) } // a new node: nothing to keep
        do {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for file in files {
                try fm.copyItem(atPath: networkDir + "/" + file, toPath: folder + "/" + file)
            }
            return .success(folder)
        } catch {
            return .failure(BackupError(message: "Couldn't back up the database: \(error.localizedDescription)"))
        }
    }

    struct BackupError: Error { let message: String }

    /// Backs up, then starts with `--database-upgrade=true`.
    func upgradeDatabaseAndStart() {
        switch backupDatabase() {
        case .success:
            start(upgradeDatabase: true)
        case .failure(let error):
            alert = error.message
        }
    }

    func stop() {
        phase = .stopping
        transitionStarted = Date()
        hideConnection()
        LightningRPC.call(socketPath: socketPath, method: "stop") { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result, error != .notRunning {
                // "stop" can drop the connection as lightningd exits: only report real errors.
                if case .rpc = error { self.alert = error.message }
            }
            self.refresh()
        }
    }

    /// FN-Server's own options. lightningd also reads ~/.lightning/<network>/config.
    private func writeConfig(prefix: String, bitcoinCli: String, withRest: Bool) throws {
        try FileManager.default.createDirectory(atPath: Self.lightningDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var lines = [
            "# Written by Fully Noded Server each time it starts Core Lightning: changes here are replaced.",
            "# Put your own options in ~/.lightning/<network>/config (lightningd reads that file too).",
            "alias=\(Self.alias())",
            "bitcoin-cli=\(bitcoinCli)",
            "bitcoin-datadir=\(Defaults.shared.bitcoinDataDir)",
            // Peers connect in only when allowed (this Mac's addresses); nothing is announced and
            // no router port is opened.
            "bind-addr=\(acceptPeersOnNetwork ? "0.0.0.0" : "127.0.0.1"):\(peerPort)",
            "proxy=127.0.0.1:\(TorClient.socksPort)"
        ]
        if peersOverTor {
            lines.append("always-use-proxy=true")
        }
        if Self.hasPlugin("cln-grpc", prefix: prefix) {
            lines += ["grpc-port=\(Self.grpcPort(network: network))"]
        }
        if withRest {
            lines += ["clnrest-port=\(restPort)", "clnrest-protocol=http", "clnrest-host=127.0.0.1"]
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: Self.confPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.confPath)
    }

    /// A compiled plugin (a file, not a folder: before v25 clnrest was a Python plugin folder
    /// that disables itself without its Python packages, and then its options stop lightningd).
    static func hasPlugin(_ name: String, prefix: String) -> Bool {
        let path = prefix + "/libexec/c-lightning/plugins/" + name
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    /// The alias from the old ~/.lightning/config if there is one (keeps an existing node's name).
    private static func alias() -> String {
        if let old = try? String(contentsOfFile: lightningDir + "/config", encoding: .utf8),
           let line = old.components(separatedBy: "\n").first(where: { $0.hasPrefix("alias=") }) {
            let alias = String(line.dropFirst("alias=".count)).trimmingCharacters(in: .whitespaces)
            if !alias.isEmpty { return alias }
        }
        return "FullyNoded-Server"
    }

    /// FN-Server's bitcoin-cli for the installed node, else Homebrew's (a core-lightning dependency).
    private func bitcoinCliPath(completion: @escaping (String?) -> Void) {
        let useKnots = UserDefaults.standard.object(forKey: "useKnots") as? Bool ?? false
        DataManager.retrieve(entityName: useKnots ? .bitcoinKnotsEnv : .bitcoinEnv) { env in
            DispatchQueue.main.async {
                let prefix = env?["prefix"] as? String ?? ""
                let home = NSHomeDirectory() + "/.fullynoded"
                let candidates = (prefix.isEmpty ? [] : [
                    "\(home)/\(useKnots ? "BitcoinKnots" : "BitcoinCore")/\(prefix)/bin/bitcoin-cli",
                    "\(home)/\(useKnots ? "BitcoinCore" : "BitcoinKnots")/\(prefix)/bin/bitcoin-cli"
                ]) + ["/opt/homebrew/bin/bitcoin-cli", "/usr/local/bin/bitcoin-cli"]
                completion(candidates.first { FileManager.default.isExecutableFile(atPath: $0) })
            }
        }
    }

    // MARK: - Polling

    func refresh() {
        guard install == .installed, !inFlight else { return }
        inFlight = true
        isRefreshing = true
        let generation = self.generation
        LightningRPC.call(socketPath: socketPath, method: "getinfo", timeout: 10) { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            self.isRefreshing = false
            guard generation == self.generation else { return }
            switch result {
            case .success(let value):
                self.handleInfo(Info(value as? [String: Any] ?? [:]))
            case .failure(let error):
                self.handleError(error)
            }
            self.readLog()
            let others = ["bitcoin", "testnet", "testnet4", "signet", "regtest"].filter {
                $0 != self.network && Self.isRunning(network: $0)
            }
            if others != self.otherRunningNetworks { self.otherRunningNetworks = others }
            let interval: TimeInterval = self.phase.isTransitioning ? 3 : (self.phase == .running ? 10 : 15)
            self.schedule(after: interval) { [weak self] in self?.refresh() }
        }
    }

    private func handleInfo(_ info: Info) {
        if phase == .stopping, let since = transitionStarted, Date().timeIntervalSince(since) < 60 { return }
        transitionStarted = nil
        self.info = info
        phase = .running
        fetchFunds()
        checkRest()
        checkPruning(lightningHeight: info.blockheight)
    }

    /// A pruned Bitcoin node keeps only recent blocks; lightningd must see every block after its
    /// last one, so if it was off for longer than that window it can never catch up.
    private func checkPruning(lightningHeight: Int) {
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let d = result as? [String: Any], d["pruned"] as? Bool == true,
                      let pruneHeight = d["pruneheight"] as? Int, let tip = d["blocks"] as? Int else {
                    if self.pruning != nil { self.pruning = nil }
                    return
                }
                // lightningd asks for the block after its height next.
                let stuck = lightningHeight > 0 && lightningHeight + 1 < pruneHeight ? lightningHeight : nil
                let pruning = Pruning(pruneHeight: pruneHeight, tipHeight: tip, stuckAt: stuck)
                if pruning != self.pruning { self.pruning = pruning }
            }
        }
    }

    /// Replaces this network's node with a new one (new node ID and keys). The old folder is
    /// renamed (moving it back restores that node: its hsm_secret holds its keys), or deleted
    /// for good when `deleteOld`. A running or hung lightningd is stopped first.
    func startFreshNode(deleteOld: Bool) {
        hideConnection()
        whenStopped { [weak self] stopped in
            guard let self else { return }
            guard stopped else {
                self.alert = "Core Lightning didn't stop, so nothing was changed."
                return
            }
            let fm = FileManager.default
            let short = { (path: String) in path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            var message: String
            do {
                if !fm.fileExists(atPath: self.networkDir) {
                    message = "Starting a new node."
                } else if deleteOld {
                    try fm.removeItem(atPath: self.networkDir)
                    message = "The old node was deleted. Starting a new node."
                } else {
                    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let kept = self.networkDir + ".old-" + stamp
                    try fm.moveItem(atPath: self.networkDir, toPath: kept)
                    message = "The old node is kept in \(short(kept)). Starting a new node."
                }
            } catch {
                self.alert = "Couldn't \(deleteOld ? "delete" : "move aside") the old node: \(error.localizedDescription). Nothing else was changed."
                return
            }
            if self.chain == "main" { message += " Back up its new hsm_secret." }
            self.info = nil
            self.funds = nil
            self.pruning = nil
            self.phase = .stopped
            self.alert = message
            self.start()
        }
    }

    /// Node folders kept by "start a new node" for this network.
    var keptOldNodes: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.lightningDir)) ?? []
        return names.filter { $0.hasPrefix(network + ".old-") }.sorted().map { Self.lightningDir + "/" + $0 }
    }

    func deleteKeptNode(_ path: String) {
        guard path.hasPrefix(Self.lightningDir + "/" + network + ".old-") else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
            objectWillChange.send()
        } catch {
            alert = "Couldn't delete \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")): \(error.localizedDescription)"
        }
    }

    /// Runs `then(true)` once lightningd isn't running: asks it to stop, and force-stops it if it
    /// doesn't (a crashed lightningd can hang instead of exiting).
    private func whenStopped(_ then: @escaping (Bool) -> Void) {
        guard processRunning else { then(true); return }
        if phase == .running { stop() }
        let started = Date()
        var forced = false
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if !self.processRunning {
                timer.invalidate()
                then(true)
            } else if !forced && (Date().timeIntervalSince(started) > 20 || self.crashedButAlive) {
                forced = true
                self.forceStop()
            } else if Date().timeIntervalSince(started) > 60 {
                timer.invalidate()
                then(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The last start crashed ("FATAL SIGNAL" after the latest startup banner) while the process
    /// is still there: lightningd can hang in its crash handler instead of exiting.
    private(set) var crashedButAlive = false

    private func lastStartCrashed() -> Bool {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        guard let data = try? handle.readToEnd() else { return false }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        let lastStart = lines.lastIndex { $0.contains("INFO    lightningd: v") } ?? -1
        let lastCrash = lines.lastIndex { $0.contains("FATAL SIGNAL") } ?? -1
        return lastCrash > lastStart
    }

    /// SIGTERM, then SIGKILL, to lightningd and its plugins / subdaemons.
    func forceStop() {
        guard let pid = NodeProcess.runningPID(pidFile: Self.pidFile(network: network), executable: "lightningd") else { return }
        let children = Self.childPIDs(of: pid)
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            for child in children where kill(child, 0) == 0 { kill(child, SIGKILL) }
            self?.crashedButAlive = false
            self?.phase = .stopped
            self?.transitionStarted = nil
            self?.refresh()
        }
    }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        guard let out = run("/usr/bin/pgrep", ["-P", "\(pid)"]) else { return [] }
        return out.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func handleError(_ error: LightningRPCError) {
        let alive = processRunning
        switch error {
        case .rpc(_, let message) where alive:
            // Answering but not ready (e.g. still loading): starting.
            if phase != .stopping { phase = .starting(message) }
            return
        default:
            break
        }
        if alive {
            if lastStartCrashed() {
                crashedButAlive = true
                let reason = brokenLogLine(since: nil).map(explain) ?? "lightningd crashed"
                phase = .failed("Core Lightning crashed and is stuck (it hasn't exited). Force stop it, then start it again or start a new node. Last error: \(reason)")
                transitionStarted = nil
                return
            }
            crashedButAlive = false
            if phase == .stopping { return }
            if case .starting = phase { return }
            phase = .starting("lightningd is starting up…")
            return
        }
        crashedButAlive = false
        info = nil
        funds = nil
        restListening = nil
        switch phase {
        case .starting:
            // Before `--daemon` returns there may be no process yet; after, none means it exited.
            if !launchReturned, let since = transitionStarted, Date().timeIntervalSince(since) < Self.startGrace { return }
            let reason = brokenLogLine(since: transitionStarted).map(explain)
            phase = .failed(reason ?? "Core Lightning stopped while starting. Its log below says why.")
            transitionStarted = nil
        case .failed, .needsDatabaseUpgrade:
            break // keep the reason (and its buttons) until the next start
        default:
            phase = .stopped
            transitionStarted = nil
            hideConnection()
        }
    }

    private func fetchFunds() {
        LightningRPC.call(socketPath: socketPath, method: "listfunds") { [weak self] result in
            guard let self, case .success(let value) = result, let d = value as? [String: Any] else { return }
            var funds = Funds()
            for output in d["outputs"] as? [[String: Any]] ?? [] {
                let sats = Self.msat(output["amount_msat"]) / 1000
                if output["status"] as? String == "confirmed" {
                    funds.onchainConfirmed += sats
                } else if output["status"] as? String == "unconfirmed" {
                    funds.onchainUnconfirmed += sats
                }
            }
            for channel in d["channels"] as? [[String: Any]] ?? [] where channel["state"] as? String == "CHANNELD_NORMAL" {
                funds.inChannels += Self.msat(channel["our_amount_msat"]) / 1000
                funds.channelCount += 1
            }
            if funds != self.funds { self.funds = funds }
        }
    }

    /// Amounts are numbers of msat (older versions: "1234msat").
    static func msat(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s.replacingOccurrences(of: "msat", with: "")) ?? 0 }
        return 0
    }

    private func checkRest() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let listening = Self.tcpListening(port: self.restPort)
            DispatchQueue.main.async { self.restListening = listening }
        }
    }

    // MARK: - Wallet connection

    /// A new rune and the onion address for a CLNRest wallet. Read-only runes can only call
    /// list*/get* methods (look, don't spend).
    func connectWallet(readOnly: Bool) {
        guard phase == .running else { return }
        if let reason = restUnavailable {
            alert = reason
            return
        }
        guard restListening == true else {
            alert = "Core Lightning's REST server (clnrest) isn't answering on port \(restPort). Restart Core Lightning; if it still doesn't, its log says why."
            return
        }
        guard let host = TorClient.sharedInstance.hostname(for: .coreLightning) else {
            alert = "Tor hasn't created Core Lightning's onion address yet. Check the Tor page: it appears once Tor is connected."
            return
        }
        var params: [String: Any] = [:]
        if readOnly {
            params["restrictions"] = [["method^list", "method^get", "method=summary"], ["method/listdatastore"]]
        }
        LightningRPC.call(socketPath: socketPath, method: "createrune", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                guard let rune = (value as? [String: Any])?["rune"] as? String else {
                    self.alert = "Core Lightning didn't return a rune."
                    return
                }
                self.connection = Connection(host: host, port: restPort, rune: rune, readOnly: readOnly)
            case .failure(let error):
                self.alert = "Couldn't create a rune: \(error.message)"
            }
        }
    }

    func hideConnection() {
        connection = nil
        plasmaNostr = nil
    }

    /// Nostr Connect relays Plasma can use: wss:// only (encrypted to the relay as well as end to end).
    static var plasmaRelays: [String] {
        NostrConnectModel.shared.pairingRelays.filter { $0.lowercased().hasPrefix("wss://") }
    }

    /// Pairs Plasma over Nostr Connect: a new rune for it (read-only when asked), kept by the
    /// bridge, which runs every request on clnrest with it (clnrest enforces it). Works wherever
    /// the phone is, through this Mac's relay or a public one: no open port, no VPN.
    func pairPlasmaOverNostr(label: String, readOnly: Bool) {
        guard phase == .running else { return }
        if let reason = restUnavailable {
            alert = reason
            return
        }
        guard restListening == true else {
            alert = "Core Lightning's REST server (clnrest) isn't answering on port \(restPort): Plasma's commands go through it. Restart Core Lightning; if it still doesn't answer, its log says why."
            return
        }
        let relays = Self.plasmaRelays
        guard !relays.isEmpty else {
            alert = "Plasma needs an encrypted (wss://) relay. In Nostr Connect turn on this Mac's relay with \"Encrypt connections (wss://)\", or add a wss:// public relay."
            return
        }
        var params: [String: Any] = [:]
        if readOnly {
            params["restrictions"] = [["method^list", "method^get", "method=summary", "method=decode"], ["method/listdatastore"]]
        }
        let chain = self.chain
        LightningRPC.call(socketPath: socketPath, method: "createrune", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                guard let rune = (value as? [String: Any])?["rune"] as? String else {
                    self.alert = "Core Lightning didn't return a rune."
                    return
                }
                guard let link = NostrConnectModel.shared.pairPlasma(label: label.isEmpty ? "Plasma" : label, chain: chain,
                                                                      rune: rune, readOnly: readOnly, relays: relays) else {
                    self.alert = "Couldn't create a Nostr Connect pairing."
                    return
                }
                self.connection = nil
                self.plasmaNostr = (link, readOnly)
            case .failure(let error):
                self.alert = "Couldn't create a rune: \(error.message)"
            }
        }
    }

    /// Lightningd listens beyond this Mac (it was started with "accept peers" on).
    var listensOnNetwork: Bool {
        info?.bindings.contains { !$0.hasPrefix("127.") && !$0.hasPrefix("[::1]") } ?? false
    }

    /// Plasma (the iOS app) can run on Apple silicon Macs and opens nostr+plasma: links.
    static var plasmaInstalledOnMac: Bool {
        guard let url = URL(string: NostrConnectURI.lightningScheme + "://check") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    /// Revokes every rune issued so far (wallets using them lose access).
    func revokeAllRunes() {
        LightningRPC.call(socketPath: socketPath, method: "showrunes") { [weak self] result in
            guard let self else { return }
            let runes = ((try? result.get()) as? [String: Any])?["runes"] as? [[String: Any]] ?? []
            let ids = runes.compactMap { ($0["unique_id"] as? String).flatMap(Int.init) ?? $0["unique_id"] as? Int }
            guard let last = ids.max() else {
                self.alert = "No runes have been issued."
                return
            }
            LightningRPC.call(socketPath: self.socketPath, method: "blacklistrune", params: ["start": 0, "end": last]) { result in
                switch result {
                case .success:
                    self.connection = nil
                    self.alert = "Revoked all \(last + 1) runes, including Plasma pairings'. Wallets connected with them need a new one, and Plasma needs pairing again."
                case .failure(let error):
                    self.alert = "Couldn't revoke runes: \(error.message)"
                }
            }
        }
    }

    func newDepositAddress() {
        LightningRPC.call(socketPath: socketPath, method: "newaddr", params: ["addresstype": "p2tr"]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let d = value as? [String: Any] ?? [:]
                self.depositAddress = d["p2tr"] as? String ?? d["bech32"] as? String
            case .failure:
                // Older versions don't know p2tr.
                LightningRPC.call(socketPath: self.socketPath, method: "newaddr") { result in
                    if case .success(let value) = result {
                        self.depositAddress = (value as? [String: Any])?["bech32"] as? String
                    } else if case .failure(let error) = result {
                        self.alert = "Couldn't get an address: \(error.message)"
                    }
                }
            }
        }
    }

    // MARK: - Files

    func openConfig() {
        let own = networkDir + "/config"
        if !FileManager.default.fileExists(atPath: own) {
            try? FileManager.default.createDirectory(atPath: networkDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? "# Your own Core Lightning options for this network (see `man lightningd-config`).\n# Fully Noded Server's are in ../fns-server.conf.\n"
                .write(toFile: own, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: own))
    }

    func openLog() {
        guard FileManager.default.fileExists(atPath: logPath) else {
            alert = "No log yet for this network."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    func showNodeFolder() {
        let path = FileManager.default.fileExists(atPath: networkDir) ? networkDir : Self.lightningDir
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func readLog() {
        let path = logPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var lines: [String] = []
            if let handle = FileHandle(forReadingAtPath: path) {
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                let chunk: UInt64 = 16 * 1024
                try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
                if let data = try? handle.readToEnd() {
                    var all = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").filter { !$0.isEmpty }
                    if size > chunk, !all.isEmpty { all.removeFirst() }
                    lines = Array(all.suffix(8))
                }
            }
            DispatchQueue.main.async {
                guard let self, path == self.logPath, self.logTail != lines else { return }
                self.logTail = lines
            }
        }
    }

    // MARK: - Helpers

    private func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) {
        timer?.invalidate()
        guard visible else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Runs a binary and returns its stdout (nil if it couldn't run).
    fileprivate static func run(_ path: String, _ arguments: [String]) -> String? {
        let result = runWithStatus(path, arguments, timeout: 30)
        return result.status == 0 ? result.stdout : nil
    }

    /// Runs a binary until it exits. Output goes to temporary files, not pipes: `lightningd
    /// --daemon` leaves children that would hold a pipe open long after it has returned.
    private static func runWithStatus(_ path: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, stdout: String, stderr: String) {
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("fns-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("fns-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        guard let out = try? FileHandle(forWritingTo: outURL), let err = try? FileHandle(forWritingTo: errURL) else {
            return (-1, "", "Couldn't create temporary files.")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = out
        task.standardError = err
        task.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do { try task.run() } catch { return (-1, "", error.localizedDescription) }
        let finished = done.wait(timeout: .now() + timeout) == .success
        try? out.close()
        try? err.close()
        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        guard finished else {
            return (-1, stdout, "\((path as NSString).lastPathComponent) didn't finish in time.")
        }
        return (task.terminationStatus, stdout, stderr)
    }

    private static func tcpListening(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
