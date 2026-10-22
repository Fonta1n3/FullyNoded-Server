//
//  JoinMarket.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//
//  The JoinMarket page: the wallet daemon (jmwalletd) Fully Noded uses for coinjoins, with
//  start / stop, what it's doing, and whether joinmarket.cfg matches the node.
//

import SwiftUI
import AppKit

final class JoinMarketMonitor: ObservableObject {
    enum Phase: Equatable {
        case unknown
        case stopped
        case starting
        case running
        case stopping
        case failed(String)

        var isTransitioning: Bool { self == .starting || self == .stopping || self == .unknown }
    }

    struct Check: Equatable {
        let ok: Bool
        let text: String
    }

    static let shared = JoinMarketMonitor()

    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var session: JMSession?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    /// joinmarket.cfg against the node: network and RPC port.
    @Published private(set) var configChecks: [Check] = []
    @Published var alert: String?

    private var timer: Timer?
    private var visible = false
    private var inFlight = false
    private var transitionStarted: Date?
    private static let startTimeout: TimeInterval = 120
    private static let stopTimeout: TimeInterval = 30

    var tagName: String { UserDefaults.standard.string(forKey: "tagName") ?? "" }

    /// "v0.9.11", or "master" for a build of the clientserver branch.
    var versionLabel: String? {
        let tag = tagName
        if tag.isEmpty { return nil }
        if tag == "clientserver" { return "master" }
        return tag.hasPrefix("v") ? tag : "v" + tag
    }

    var configMatches: Bool { configChecks.allSatisfy(\.ok) }

    // MARK: - Lifecycle

    func appear() {
        visible = true
        checkConfig()
        refresh()
    }

    func disappear() {
        visible = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    /// Checks the node first: jmwalletd needs bitcoind's RPC.
    func start() {
        phase = .starting
        transitionStarted = Date()
        lastError = nil
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if result is [String: Any] {
                    self.launch()
                } else if let warmup = result as? String, warmup.isEmpty {
                    self.abortStart("Your node is still starting up. Start JoinMarket once it shows Running.")
                } else if let error, NodeMonitor.isUnreachable(error) {
                    self.abortStart("Your node isn't running. Start Bitcoin Core (or Knots) first: JoinMarket uses its RPC.")
                } else if let error, error.contains("credentials") || error.contains("No BitcoinRPCCreds") {
                    self.abortStart(error)
                } else {
                    // Busy (loading, verifying…): JoinMarket waits for the RPC itself.
                    self.launch()
                }
            }
        }
    }

    private func abortStart(_ message: String) {
        phase = .stopped
        transitionStarted = nil
        alert = message
    }

    private func launch() {
        if TorClient.sharedInstance.state != .connected {
            lastError = "Tor isn't connected yet: JoinMarket needs it to reach other coinjoin participants."
        }
        ConfigureJM.configureNetwork()
        checkConfig()
        removeLockFiles()
        ScriptUtil.runScript(script: .launchJmStarter, env: ["TAG_NAME": tagName], args: nil) { [weak self] _, _, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMessage, !errorMessage.isEmpty {
                    self.phase = .failed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                    self.transitionStarted = nil
                    return
                }
                self.refresh()
            }
        }
    }

    func stop() {
        phase = .stopping
        transitionStarted = Date()
        ScriptUtil.runScript(script: .stopJm, env: nil, args: nil) { [weak self] _, _, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMessage, !errorMessage.isEmpty { self.lastError = errorMessage }
                self.refresh()
            }
        }
    }

    /// Rewrites joinmarket.cfg's network and RPC port to match the node.
    func fixConfig() {
        ConfigureJM.configureNetwork()
        checkConfig()
        if phase == .running {
            alert = "joinmarket.cfg updated. Stop and start JoinMarket for it to take effect."
        }
    }

    func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: ConfigureJM.confPath))
    }

    // MARK: - Polling

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        isRefreshing = true
        JMRPC.sharedInstance.command(method: .session, param: nil) { [weak self] response, error in
            guard let self else { return }
            self.inFlight = false
            self.isRefreshing = false
            if let response = response as? [String: Any] {
                self.handleSession(JMSession(response))
            } else {
                self.handleError(error ?? "")
            }
            self.schedule()
        }
    }

    private func handleSession(_ session: JMSession) {
        self.session = session
        if phase == .stopping, let since = transitionStarted, Date().timeIntervalSince(since) < Self.stopTimeout {
            return // still shutting down
        }
        if phase == .stopping {
            alert = "JoinMarket is still running. Close its Terminal window (startJoinMarket.sh) to stop it."
        }
        transitionStarted = nil
        phase = .running
        if lastError?.hasPrefix("Tor") == true, TorClient.sharedInstance.state == .connected { lastError = nil }
    }

    private func handleError(_ error: String) {
        let unreachable = error.isEmpty || NodeMonitor.isUnreachable(error)
        guard unreachable else {
            // Up but unhappy (HTTP error, …): say so on the page rather than in an alert per poll.
            lastError = error
            if phase == .unknown { phase = .running }
            return
        }
        session = nil
        switch phase {
        case .starting:
            let elapsed = Date().timeIntervalSince(transitionStarted ?? Date())
            // jmwalletd takes a few seconds to open its port; if it isn't even running after a
            // while (Python error, …), say so instead of waiting for the full timeout.
            if elapsed > Self.startTimeout || (elapsed > 20 && !Self.daemonRunning()) {
                phase = .failed("JoinMarket didn't start. Its Terminal window (startJoinMarket.sh) shows why.")
                transitionStarted = nil
            }
        case .failed:
            break // keep the reason on screen until the next start
        default:
            phase = .stopped
            transitionStarted = nil
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard visible else { return }
        let interval: TimeInterval = phase.isTransitioning ? 2 : (phase == .running ? 10 : 15)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Helpers

    private func checkConfig() {
        guard FileManager.default.fileExists(atPath: ConfigureJM.confPath) else {
            configChecks = [Check(ok: false, text: "No joinmarket.cfg yet: JoinMarket creates it on its first start.")]
            return
        }
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        let port = UserDefaults.standard.string(forKey: "port") ?? "8332"
        let network = ConfigureJM.confValue("network") ?? "?"
        let rpcPort = ConfigureJM.confValue("rpc_port") ?? "?"
        let expectedNetwork = ConfigureJM.jmNetwork(chain: chain)
        configChecks = [
            Check(ok: network == expectedNetwork,
                  text: network == expectedNetwork ? "network = \(network)" : "network = \(network), but your node is on \(NodeMonitor.networkName(chain)) (\(expectedNetwork))"),
            Check(ok: rpcPort == port,
                  text: rpcPort == port ? "rpc_port = \(rpcPort)" : "rpc_port = \(rpcPort), but your node's RPC is on \(port)")
        ]
    }

    /// Stale wallet .lock files (left by a crash) stop jmwalletd from opening the wallet.
    private func removeLockFiles() {
        let path = "/Users/\(NSUserName())/Library/Application Support/joinmarket/wallets"
        guard !Self.daemonRunning(), let files = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for file in files where file.hasSuffix(".lock") {
            try? FileManager.default.removeItem(atPath: path + "/" + file)
        }
    }

    /// jmwalletd.py is running for this user.
    static func daemonRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-u", "\(getuid())", "-f", "jmwalletd.py"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct JoinMarket: View {
    @ObservedObject private var monitor = JoinMarketMonitor.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                if monitor.phase == .running {
                    sessionCard
                }
                configCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 420)
        .onAppear { monitor.appear() }
        .onDisappear { monitor.disappear() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { monitor.appear() } else { monitor.disappear() }
        }
        .alert(monitor.alert ?? "", isPresented: Binding(
            get: { monitor.alert != nil },
            set: { if !$0 { monitor.alert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .alert("Stop JoinMarket?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { monitor.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(monitor.session?.coinjoin_in_process == true
                 ? "A coinjoin is in progress: stopping now abandons it (your coins stay safe in your wallet)."
                 : "Fully Noded's JoinMarket wallets go offline, and a running maker stops offering coinjoins.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("JoinMarket")
                    .font(Cypher.mono(20, weight: .bold))
                if let version = monitor.versionLabel {
                    Text(version)
                        .font(Cypher.mono(12))
                        .foregroundStyle(Cypher.dim)
                }
                Spacer()
                Button {
                    openWindow(id: "QuickConnect-JM")
                } label: {
                    Image(systemName: "qrcode")
                    Text("Quick Connect")
                }
                .help("Connect Fully Noded's JoinMarket wallet to this daemon")
                Button {
                    openWindow(id: "Utilities-JM")
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .help("Utilities: configure, rescan, gap limit, order book")
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(monitor.isRefreshing ? 360 : 0))
                        .animation(monitor.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                   value: monitor.isRefreshing)
                }
                .help("Refresh")
            }
            Text("Coinjoins for Fully Noded. The JoinMarket wallet daemon runs on this Mac against your own node and talks to other participants over Tor; Fully Noded controls it over its onion address.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        GroupBox("Wallet daemon") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(Cypher.mono(16, weight: .bold))
                            .foregroundStyle(statusColor)
                        Text(statusDetail)
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    switch monitor.phase {
                    case .stopped, .failed:
                        Button {
                            monitor.start()
                        } label: {
                            Image(systemName: "play.fill")
                            Text("Start")
                        }
                        .buttonStyle(.cypherProminent)
                    case .running:
                        Button {
                            confirmStop = true
                        } label: {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                    case .starting, .stopping, .unknown:
                        ProgressView().controlSize(.small)
                    }
                }
                if case .failed(let reason) = monitor.phase {
                    Text(reason)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusColor: Color {
        switch monitor.phase {
        case .running: return Cypher.accent
        case .starting, .stopping, .unknown: return Cypher.amber
        case .stopped, .failed: return Cypher.danger
        }
    }

    private var statusTitle: String {
        switch monitor.phase {
        case .unknown: return "Checking…"
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .running: return monitor.session?.coinjoin_in_process == true ? "Coinjoining" : "Running"
        case .failed: return "Didn't start"
        }
    }

    private var statusDetail: String {
        switch monitor.phase {
        case .unknown: return "Looking for jmwalletd on localhost:\(JMRPC.port)."
        case .stopped: return "Start it to use JoinMarket wallets in Fully Noded. Your node must be running."
        case .starting: return "A Terminal window opens and runs jmwalletd. Keep it open while you use JoinMarket."
        case .stopping: return "Stopping jmwalletd and closing its Terminal window."
        case .running: return "jmwalletd on https://localhost:\(JMRPC.port)"
        case .failed: return "See its Terminal window for details."
        }
    }

    // MARK: - Session

    private var sessionCard: some View {
        GroupBox("Session") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass")
                        .foregroundStyle(Cypher.dim)
                    if let wallet = monitor.session?.wallet_name {
                        Text(wallet)
                            .font(Cypher.mono(12, weight: .semibold))
                            .textSelection(.enabled)
                    } else {
                        Text("No wallet open. Unlock one from Fully Noded.")
                            .font(Cypher.mono(12))
                            .foregroundStyle(Cypher.dim)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .topLeading)],
                          alignment: .leading, spacing: 10) {
                    JMFlagTile(label: "Wallet session", on: monitor.session?.session == true,
                               onText: "active", offText: "none", systemImage: "wifi.circle")
                    JMFlagTile(label: "Coinjoin", on: monitor.session?.coinjoin_in_process == true,
                               onText: "in progress", offText: "idle", systemImage: "arrow.trianglehead.2.clockwise")
                    JMFlagTile(label: "Maker", on: monitor.session?.maker_running == true,
                               onText: "offering coinjoins", offText: "off", systemImage: "bitcoinsign.circle")
                }
            }
        }
    }

    // MARK: - Config

    private var configCard: some View {
        GroupBox("joinmarket.cfg") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(monitor.configChecks, id: \.text) { check in
                    Label {
                        Text(check.text)
                            .font(Cypher.mono(11))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(check.ok ? Cypher.accent : Cypher.amber)
                    }
                }
                HStack(spacing: 8) {
                    if !monitor.configMatches && FileManager.default.fileExists(atPath: ConfigureJM.confPath) {
                        Button {
                            monitor.fixConfig()
                        } label: {
                            Image(systemName: "wand.and.stars")
                            Text("Match my node")
                        }
                        .buttonStyle(.cypherProminent)
                    }
                    Button {
                        monitor.openConfig()
                    } label: {
                        Image(systemName: "doc.text")
                        Text("Open joinmarket.cfg")
                    }
                    .disabled(!FileManager.default.fileExists(atPath: ConfigureJM.confPath))
                }
            }
        }
    }
}

private struct JMFlagTile: View {
    let label: String
    let on: Bool
    let onText: String
    let offText: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Cypher.mono(9.5, weight: .bold))
                .foregroundStyle(Cypher.dim)
            Label(on ? onText : offText, systemImage: systemImage)
                .font(Cypher.mono(13, weight: .semibold))
                .foregroundStyle(on ? Cypher.accent : Cypher.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cypher.bg)
        .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

#Preview {
    JoinMarket()
}
