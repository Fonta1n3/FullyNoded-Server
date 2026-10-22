//
//  NodeView.swift
//  FullyNoded-Server
//
//  The Bitcoin Core / Bitcoin Knots page: status with start and stop, network, sync progress
//  with time left, live stats and the end of debug.log. State comes from NodeMonitor.
//

import SwiftUI

struct NodeView: View {
    @ObservedObject var monitor: NodeMonitor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                if let info = monitor.info, monitor.phase == .running {
                    syncCard(info)
                    statsCard(info)
                }
                logCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 480)
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
        .alert("Stop \(monitor.kind.name)?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { monitor.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fully Noded and anything else using this node (JoinMarket, Silent Payments) lose their connection until it's started again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text(monitor.kind.name)
                    .font(Cypher.mono(20, weight: .bold))
                if let version = monitor.version {
                    Text("v\(version)")
                        .font(Cypher.mono(12))
                        .foregroundStyle(Cypher.dim)
                }
                Spacer()
                Button {
                    openWindow(id: "QuickConnect")
                } label: {
                    Image(systemName: "qrcode")
                    Text("Quick Connect")
                }
                .help("Connect Fully Noded to this node")
                Button {
                    openWindow(id: monitor.kind.utilitiesWindow)
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .help("Utilities: bitcoin.conf, rpc credentials, reindex, …")
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
            Text("Your own full node on this Mac. Fully Noded connects to it over Tor or Nostr Connect, so your wallets never ask anyone else about your coins.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        GroupBox("Node") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    StatusDot(color: statusColor, pulsing: monitor.phase.isTransitioning || monitor.phase == .unknown)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(Cypher.mono(16, weight: .bold))
                            .foregroundStyle(statusColor)
                        if let detail = statusDetail {
                            Text(detail)
                                .font(Cypher.mono(11))
                                .foregroundStyle(Cypher.dim)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    primaryButton
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(Cypher.dim)
                    Picker("Network", selection: Binding(get: { monitor.chain }, set: { monitor.setChain($0) })) {
                        ForEach(monitor.kind.chains, id: \.self) { chain in
                            Text(NodeMonitor.networkName(chain)).tag(chain)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(monitor.phase.isTransitioning)
                    Text("RPC port \(NodeMonitor.rpcPort(chain: monitor.chain))")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                    Spacer()
                    if !monitor.otherRunningChains.isEmpty {
                        Label("Also running: \(monitor.otherRunningChains.map(NodeMonitor.networkName).joined(separator: ", "))",
                              systemImage: "circle.fill")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.amber)
                            .help("A bitcoind for another network is running from this data folder. Switch to it to see or stop it.")
                    }
                }

                if case .failed(let reason) = monitor.phase {
                    Text(reason)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
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
            ProgressView()
                .controlSize(.small)
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
        case .failed: return "Didn't start"
        case .running:
            guard let info = monitor.info else { return "Running" }
            return info.verificationprogress > 0.9999 && !info.initialblockdownload ? "Running" : "Syncing"
        }
    }

    private var statusDetail: String? {
        switch monitor.phase {
        case .starting(let message): return message
        case .stopping: return "Saving its state to disk. This can take a minute."
        case .stopped: return "Start it to use Fully Noded with this node on \(NodeMonitor.networkName(monitor.chain))."
        case .running:
            guard let info = monitor.info else { return nil }
            var parts = ["Block \(info.blocks.withCommas)"]
            if let age = tipAge(info) { parts.append("tip \(age)") }
            if let peers = monitor.peers { parts.append("\(peers.inbound + peers.outbound) peers") }
            return parts.joined(separator: " · ")
        case .unknown, .failed: return nil
        }
    }

    // MARK: - Sync

    private func syncCard(_ info: BlockchainInfo) -> some View {
        GroupBox("Sync") {
            VStack(alignment: .leading, spacing: 10) {
                if info.verificationprogress > 0.9999 && !info.initialblockdownload {
                    Label {
                        Text("Fully verified")
                            .font(Cypher.mono(13, weight: .semibold))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Cypher.accent)
                    }
                    Text("Every block since the genesis block was checked by this Mac\(info.pruned ? " (older blocks then pruned to save space)" : "").")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.2f%%", min(info.verificationprogress, 1) * 100))
                            .font(Cypher.mono(22, weight: .bold))
                            .foregroundStyle(Cypher.accent)
                            .contentTransition(.numericText())
                        Text(info.initialblockdownload ? "downloading and verifying the blockchain" : "verifying")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.dim)
                        Spacer()
                        if let timeLeft = monitor.timeLeft {
                            Text("~\(Self.duration(timeLeft)) left")
                                .font(Cypher.mono(12, weight: .semibold))
                        } else {
                            Text("estimating time left…")
                                .font(Cypher.mono(11))
                                .foregroundStyle(Cypher.dim)
                        }
                    }
                    SyncBar(progress: info.verificationprogress)
                    Text(info.headers > 0
                         ? "Block \(info.blocks.withCommas) of \(info.headers.withCommas)"
                         : "Block \(info.blocks.withCommas)")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                    Text("Keep this Mac awake and online. The first sync takes hours to days depending on its disk and connection; Fully Noded can connect meanwhile but sees balances only once it's done.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !info.warnings.isEmpty {
                    Label(info.warnings, systemImage: "exclamationmark.triangle.fill")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Stats

    private func statsCard(_ info: BlockchainInfo) -> some View {
        GroupBox("Stats") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .topLeading)],
                      alignment: .leading, spacing: 10) {
                StatTile(label: "Height", value: info.blocks.withCommas)
                StatTile(label: "Peers", value: monitor.peers.map { "\($0.outbound) out · \($0.inbound) in" } ?? "—")
                StatTile(label: "Mempool", value: monitor.mempool.map { "\($0.count.withCommas) tx" } ?? "—",
                         detail: monitor.mempool.map { Self.bytes($0.bytes) })
                StatTile(label: info.pruned ? "Disk (pruned)" : "Disk", value: Self.bytes(info.size_on_disk),
                         detail: info.pruned && info.pruneheight > 0 ? "from block \(info.pruneheight.withCommas)" : nil)
                StatTile(label: "Uptime", value: monitor.uptime.map { Self.duration(TimeInterval($0)) } ?? "—")
                StatTile(label: "Tor", value: monitor.onionReachable.map { $0 ? "onion reachable" : "off" } ?? "—",
                         valueColor: monitor.onionReachable == true ? Cypher.accent : nil)
                StatTile(label: "Version", value: monitor.subversion ?? monitor.version.map { "v\($0)" } ?? "—")
                StatTile(label: "Network", value: NodeMonitor.networkName(monitor.chain))
            }
        }
    }

    // MARK: - Log

    private var logCard: some View {
        GroupBox("debug.log") {
            VStack(alignment: .leading, spacing: 10) {
                if monitor.logTail.isEmpty {
                    Text("No log yet for \(NodeMonitor.networkName(monitor.chain)).")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(monitor.logTail.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(Cypher.mono(10.5))
                                .foregroundStyle(index == monitor.logTail.count - 1 ? Cypher.text : Cypher.dim)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Cypher.bg)
                }
                HStack(spacing: 8) {
                    Button {
                        monitor.openDebugLog()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Open debug.log")
                    }
                    Button {
                        monitor.showDataFolder()
                    } label: {
                        Image(systemName: "folder")
                        Text("Show data folder")
                    }
                }
            }
        }
    }

    // MARK: - Formatting

    private func tipAge(_ info: BlockchainInfo) -> String? {
        guard info.time > 0 else { return nil }
        let seconds = max(0, Date().timeIntervalSince1970 - TimeInterval(info.time))
        return seconds < 60 ? "just now" : "\(Self.duration(seconds)) ago"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let days = s / 86_400, hours = (s % 86_400) / 3600, minutes = (s % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// The node's status light; breathes while something is under way.
private struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 22, height: 22)
                .scaleEffect(pulsing && pulse ? 1.35 : 1)
                .opacity(pulsing && pulse ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.8), radius: 4)
        }
        .onAppear { pulse = true }
        .animation(pulsing ? .easeOut(duration: 1.2).repeatForever(autoreverses: false) : .default, value: pulse)
        .animation(.default, value: pulsing)
    }
}

/// Square, terminal-style progress bar.
private struct SyncBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Cypher.bg)
                Rectangle()
                    .fill(LinearGradient(colors: [Cypher.accent.opacity(0.55), Cypher.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    .animation(.easeInOut(duration: 0.6), value: progress)
            }
            .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
        }
        .frame(height: 10)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Cypher.mono(9.5, weight: .bold))
                .foregroundStyle(Cypher.dim)
            Text(value)
                .font(Cypher.mono(13, weight: .semibold))
                .foregroundStyle(valueColor ?? Cypher.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
            if let detail {
                Text(detail)
                    .font(Cypher.mono(10))
                    .foregroundStyle(Cypher.dim)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cypher.bg)
        .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
