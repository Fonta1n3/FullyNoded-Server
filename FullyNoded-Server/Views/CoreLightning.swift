//
//  CoreLightning.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/11/24.
//
//  The Core Lightning page: install with Homebrew, start / stop, the node's channels and funds,
//  and connecting a CLNRest wallet over Tor. State comes from LightningNode.
//

import SwiftUI
import AppKit

struct CoreLightning: View {
    @Environment(\.cypherPalette) private var palette
    @ObservedObject private var node = LightningNode.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmStop = false
    @State private var confirmRevoke = false
    @State private var confirmDatabaseUpgrade = false
    @State private var confirmFreshNode = false
    @State private var deleteKept: String?
    @State private var copied: String?
    @State private var plasmaLabel = ""
    @ObservedObject private var nostr = NostrConnectModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if node.install == .installed {
                    statusCard
                    if node.phase == .running, let info = node.info {
                        nodeCard(info)
                        plasmaCard
                        connectCard
                    }
                    settingsCard
                    logCard
                } else {
                    setupCard
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 480)
        .onAppear { node.appear() }
        .onDisappear {
            node.disappear()
            node.hideConnection()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                node.appear()
            } else {
                node.disappear()
                node.hideConnection() // a rune on screen shouldn't outlive the window's focus
            }
        }
        .alert(node.alert ?? "", isPresented: Binding(
            get: { node.alert != nil },
            set: { if !$0 { node.alert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .alert("Stop Core Lightning?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { node.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Payments can't be sent or received and your channels' peers see you offline until it's started again. Your funds stay safe.")
        }
        .alert("Upgrade the node's database?", isPresented: $confirmDatabaseUpgrade) {
            Button("Back up and upgrade") { node.upgradeDatabaseAndStart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Core Lightning starts with --database-upgrade=true. The database is copied to fns-backups first, but older versions can't use the upgraded one, and restoring an old copy after channels have moved on can lose funds.")
        }
        .confirmationDialog("Start a new \(NodeMonitor.networkName(node.chain)) Lightning node?", isPresented: $confirmFreshNode, titleVisibility: .visible) {
            Button("Keep the old node (rename it)") { node.startFreshNode(deleteOld: false) }
            Button("Delete the old node", role: .destructive) { node.startFreshNode(deleteOld: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(node.chain == "main"
                 ? "A new node with a new node ID and keys is created. Keeping the old one renames its folder to \(node.network).old-<date>. Deleting it erases its hsm_secret and database for good: any funds it still has are lost unless you have a backup."
                 : "A new node with a new node ID is created. Keeping the old one renames its folder to \(node.network).old-<date>; deleting it removes it for good. Only test coins are involved.")
        }
        .alert("Revoke all runes?", isPresented: $confirmRevoke) {
            Button("Revoke", role: .destructive) { node.revokeAllRunes() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every wallet connected with a rune from this node loses access and needs a new one.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("Core Lightning")
                    .font(Cypher.mono(20, weight: .bold))
                if let version = node.version {
                    Text("v\(version)")
                        .font(Cypher.mono(12))
                        .foregroundStyle(Cypher.dim)
                }
                Spacer()
                if node.install == .installed {
                    Button {
                        node.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(node.isRefreshing ? 360 : 0))
                            .animation(node.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                       value: node.isRefreshing)
                    }
                    .help("Refresh")
                }
            }
            Text("A Lightning node on top of your own Bitcoin node, made for Plasma on your iPhone. It reaches peers through Tor; Plasma connects to it directly over the Lightning protocol, other wallets over its onion address.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        GroupBox("Set up") {
            VStack(alignment: .leading, spacing: 12) {
                switch node.install {
                case .checking:
                    ProgressView().controlSize(.small)
                case .needsHomebrew:
                    setupText("Core Lightning is installed with Homebrew, the macOS package manager. Install Homebrew first: its installer opens in Terminal.")
                    HStack(spacing: 8) {
                        Button {
                            node.installHomebrew()
                        } label: {
                            Image(systemName: "shippingbox")
                            Text("Install Homebrew")
                        }
                        .buttonStyle(.cypherProminent)
                        Button("Check again") { node.checkInstall() }
                    }
                case .notInstalled, .failed:
                    if case .failed(let reason) = node.install {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    setupText("Homebrew installs Core Lightning in a Terminal window (a few minutes). Fully Noded Server then configures it for you: it uses your Bitcoin node's network, reaches peers through Tor and serves wallets over an onion address.")
                    if node.hasExistingNode {
                        Label("A Core Lightning node already exists in \(node.networkDir.replacingOccurrences(of: NSHomeDirectory(), with: "~")). It's used as it is: nothing in it is changed.",
                              systemImage: "checkmark.shield")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        node.installOrUpdate()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                        Text(node.install == .notInstalled ? "Install Core Lightning" : "Try again")
                    }
                    .buttonStyle(.cypherProminent)
                case .installing:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        setupText("Homebrew is installing Core Lightning in Terminal. This page continues by itself when it's done.")
                    }
                    Button("Check again") { node.checkInstall() }
                case .installed:
                    EmptyView()
                }
            }
        }
    }

    private func setupText(_ text: String) -> some View {
        Text(text)
            .font(Cypher.mono(12))
            .foregroundStyle(Cypher.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status

    private var statusCard: some View {
        GroupBox("Node") {
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
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    switch node.phase {
                    case .needsDatabaseUpgrade:
                        EmptyView()
                    case .failed where node.crashedButAlive:
                        Button {
                            node.forceStop()
                        } label: {
                            Image(systemName: "xmark.octagon")
                            Text("Force stop")
                        }
                        .buttonStyle(.cypherProminent)
                    case .stopped, .failed:
                        Button {
                            node.start()
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

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(Cypher.dim)
                    Text("\(NodeMonitor.networkName(node.chain)), following your Bitcoin node")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                    Spacer()
                    if !node.otherRunningNetworks.isEmpty {
                        Label("Also running: \(node.otherRunningNetworks.joined(separator: ", "))", systemImage: "circle.fill")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.amber)
                            .help("A lightningd for another network is running. Switch your Bitcoin node to that network to see or stop it.")
                    }
                }

                if case .failed(let reason) = node.phase {
                    Text(reason)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if node.hasExistingNode {
                        Button {
                            confirmFreshNode = true
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("Start a new node…")
                        }
                        .help("Replace this network's node with a new one; keep or delete the old one")
                    }
                }

                if case .needsDatabaseUpgrade(let detail) = node.phase {
                    databaseUpgradeBox(detail)
                }

                if node.phase == .running, let pruning = node.pruning, let stuck = pruning.stuckAt {
                    prunedStuckBox(stuck: stuck, pruning: pruning)
                }

                if let latest = node.updateAvailable {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Cypher.accent)
                        Text("Core Lightning \(latest) is available.\(node.phase == .running ? " Stop the node to update." : "")")
                            .font(Cypher.mono(11))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Update") { node.installOrUpdate() }
                            .disabled(node.phase != .stopped && !(node.phase.isFailed))
                            .help("Updates with Homebrew in Terminal. The node's database is upgraded on its next start (there's no going back to an older version).")
                    }
                }
                if node.install == .installing {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Homebrew is updating Core Lightning in Terminal…")
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.dim)
                    }
                }
            }
        }
    }

    private func prunedStuckBox(stuck: Int, pruning: LightningNode.Pruning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Core Lightning can't catch up", systemImage: "exclamationmark.triangle.fill")
                .font(Cypher.mono(12, weight: .bold))
                .foregroundStyle(Cypher.amber)
            Text("It last saw block \(stuck.withCommas) and needs every block after it, but your Bitcoin node is pruned and only keeps blocks from \(pruning.pruneHeight.withCommas) on. It will keep waiting for blocks that are gone.")
                .font(Cypher.mono(11))
                .fixedSize(horizontal: false, vertical: true)
            Text(node.chain == "main"
                 ? "Start a new Lightning node (the old one is kept, renamed). To keep this one instead, turn off pruning in bitcoin.conf and reindex your Bitcoin node: the full mainnet chain, ~\(SetupAssistant.fullSizeGB(chain: "main")) GB and days of syncing."
                 : "On \(NodeMonitor.networkName(node.chain)) the coins have no value, so the easy fix is a new Lightning node (the old one is kept, renamed).")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                confirmFreshNode = true
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                Text("Start a new node")
            }
            .buttonStyle(.cypherProminent)
        }
        .padding(10)
        .background(Cypher.bg)
        .overlay(Rectangle().stroke(Cypher.amber.opacity(0.5), lineWidth: 1))
    }

    private func databaseUpgradeBox(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("lightningd: refusing to upgrade the database \(detail).")
                .font(Cypher.mono(10.5))
                .foregroundStyle(Cypher.dim)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Upgrading is one-way: older Core Lightning versions can't open the database afterwards. FN-Server copies it to \(node.networkDir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))/fns-backups/ first.\(node.updateAvailable.map { " Updating to \($0) also upgrades it, and brings fixes and the built-in REST server." } ?? "")")
                .font(Cypher.mono(11))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let latest = node.updateAvailable {
                    Button {
                        node.installOrUpdate()
                    } label: {
                        Image(systemName: "arrow.up.circle")
                        Text("Update to \(latest)")
                    }
                    .buttonStyle(.cypherProminent)
                }
                Button {
                    confirmDatabaseUpgrade = true
                } label: {
                    Image(systemName: "cylinder.split.1x2")
                    Text(node.updateAvailable == nil ? "Upgrade database and start" : "Upgrade on this version")
                }
            }
        }
        .padding(10)
        .background(Cypher.bg)
        .overlay(Rectangle().stroke(Cypher.amber.opacity(0.5), lineWidth: 1))
    }

    private var statusColor: Color {
        switch node.phase {
        case .running: return palette.accent
        case .starting, .stopping, .unknown, .needsDatabaseUpgrade: return Cypher.amber
        case .stopped, .failed: return Cypher.danger
        }
    }

    private var statusTitle: String {
        switch node.phase {
        case .unknown: return "Checking…"
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .failed: return "Didn't start"
        case .needsDatabaseUpgrade: return "Database upgrade needed"
        case .running: return node.info?.warnings.isEmpty == false ? "Syncing" : "Running"
        }
    }

    private var statusDetail: String {
        switch node.phase {
        case .unknown: return "Looking for lightningd…"
        case .stopped: return node.hasExistingNode ? "Your node's data is ready to start." : "Starting it for the first time creates a new node (its keys are in hsm_secret: back it up)."
        case .starting(let message): return message
        case .stopping: return "Closing connections and saving its state."
        case .failed: return "See the reason below and the log."
        case .needsDatabaseUpgrade(let detail): return "Your node's database was made by an older Core Lightning. This version (\(detail.components(separatedBy: "non-final version ").last ?? "installed") won't upgrade it by itself."
        case .running:
            guard let info = node.info else { return "" }
            return "Block \(info.blockheight.withCommas) · \(info.peers) peers · \(info.activeChannels) channels"
        }
    }

    // MARK: - Node

    private func nodeCard(_ info: LightningNode.Info) -> some View {
        GroupBox("Your node") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: info.color) ?? palette.accent)
                        .frame(width: 12, height: 12)
                    Text(info.alias.isEmpty ? "No alias" : info.alias)
                        .font(Cypher.mono(13, weight: .semibold))
                }
                HStack(spacing: 8) {
                    Text(info.id)
                        .font(Cypher.mono(10.5))
                        .foregroundStyle(Cypher.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button {
                        copy(info.id, id: "nodeid")
                    } label: {
                        Image(systemName: copied == "nodeid" ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy the node ID")
                }
                ForEach(info.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .topLeading)],
                          alignment: .leading, spacing: 10) {
                    LNTile(label: "In channels", value: node.funds.map { Self.sats($0.inChannels) } ?? "—",
                           detail: node.funds.map { "\($0.channelCount) open" })
                    LNTile(label: "On-chain", value: node.funds.map { Self.sats($0.onchainConfirmed) } ?? "—",
                           detail: node.funds.flatMap { $0.onchainUnconfirmed > 0 ? "+\(Self.sats($0.onchainUnconfirmed)) unconfirmed" : nil })
                    LNTile(label: "Channels", value: "\(info.activeChannels) active",
                           detail: "\(info.pendingChannels) pending · \(info.inactiveChannels) inactive")
                    LNTile(label: "Peers", value: "\(info.peers)")
                    LNTile(label: "Block height", value: info.blockheight.withCommas)
                    LNTile(label: "REST (clnrest)", value: node.restListening.map { $0 ? "listening" : "off" } ?? "—",
                           detail: "127.0.0.1:\(node.restPort)",
                           valueColor: node.restListening == true ? palette.accent : nil)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        node.newDepositAddress()
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                        Text("New deposit address")
                    }
                    .help("An address of this node's on-chain wallet, to fund channels")
                    if let address = node.depositAddress {
                        HStack(spacing: 8) {
                            Text(address)
                                .font(Cypher.mono(11))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                copy(address, id: "address")
                            } label: {
                                Image(systemName: copied == "address" ? "checkmark" : "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Plasma

    private var plasmaCard: some View {
        GroupBox("Pair Plasma") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("RECOMMENDED")
                        .font(Cypher.mono(9, weight: .bold))
                        .foregroundStyle(Cypher.bg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Cypher.accent)
                    Text("Plasma, the Core Lightning wallet for iPhone")
                        .font(Cypher.mono(12, weight: .semibold))
                    Spacer()
                    Link(destination: LightningNode.plasmaAppStore) {
                        Label("Get Plasma", systemImage: "arrow.up.right.square")
                            .font(Cypher.mono(11))
                    }
                }
                nostrPairing
            }
        }
        .onAppear { nostr.refresh() }
    }

    // MARK: Plasma over Nostr Connect

    @ViewBuilder
    private var nostrPairing: some View {
        Text("Plasma connects through Nostr Connect, like Fully Noded: each command is end-to-end encrypted (NIP-44) and sent through a wss:// relay to this Mac, which runs it on Core Lightning's REST API (clnrest) with the pairing's rune. Works on any network, with no open port and no VPN. A read-only pairing can't spend, and removing a pairing cuts that phone off.")
            .font(Cypher.mono(11))
            .foregroundStyle(Cypher.dim)
            .fixedSize(horizontal: false, vertical: true)

        if let reason = node.restUnavailable {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.amber)
                .fixedSize(horizontal: false, vertical: true)
        } else if node.restListening == false {
            Label("clnrest isn't answering on port \(String(node.restPort)). Plasma's commands go through it: restart Core Lightning.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.amber)
                .fixedSize(horizontal: false, vertical: true)
        }

        if LightningNode.plasmaRelays.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Cypher.amber)
                VStack(alignment: .leading, spacing: 6) {
                    Text(nostr.pairingRelays.isEmpty
                         ? "Nostr Connect has no relay yet. Turn on this Mac's relay with \"Encrypt connections (wss://)\" (home and VPN), and add a wss:// public relay to reach the node from anywhere."
                         : "Plasma needs encrypted wss:// relays. Turn on \"Encrypt connections (wss://)\" for this Mac's relay, or add a wss:// public relay.")
                        .font(Cypher.mono(11))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set up Nostr Connect") { openWindow(id: "NostrConnect") }
                }
            }
        } else {
            Text("Relays in the pairing: \(LightningNode.plasmaRelays.joined(separator: ", "))")
                .font(Cypher.mono(10.5))
                .foregroundStyle(Cypher.dim)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if !LightningNode.plasmaRelays.contains(where: { !$0.contains("127.0.0.1") && !NostrRelay.lanAddresses().contains(where: $0.contains) && !NostrRelay.vpnAddresses().contains(where: $0.contains) }) {
                Text("Only this Mac's relay is in the pairing, so Plasma connects at home (or over a VPN). Add a public relay in Nostr Connect to use it anywhere, then pair again.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let pairing = node.plasmaNostr {
            nostrPairingView(link: pairing.link, readOnly: pairing.readOnly)
        } else {
            HStack(spacing: 8) {
                TextField("Name (e.g. My iPhone)", text: $plasmaLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button {
                    node.pairPlasmaOverNostr(label: plasmaLabel, readOnly: false)
                } label: {
                    Image(systemName: "qrcode")
                    Text("Pair Plasma")
                }
                .buttonStyle(.cypherProminent)
                .disabled(LightningNode.plasmaRelays.isEmpty || node.restUnavailable != nil)
                .help("Plasma can do anything: pay, receive, open channels")
                Button {
                    node.pairPlasmaOverNostr(label: plasmaLabel, readOnly: true)
                } label: {
                    Image(systemName: "eye")
                    Text("Read-only")
                }
                .disabled(LightningNode.plasmaRelays.isEmpty || node.restUnavailable != nil)
                .help("Plasma can only view balances, channels and invoices")
            }
        }

        let paired = nostr.pairings.filter { $0.isLightning && $0.chain == node.chain }
        if !paired.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("PAIRED OVER NOSTR CONNECT")
                    .font(Cypher.mono(9.5, weight: .bold))
                    .foregroundStyle(Cypher.dim)
                ForEach(paired) { pairing in
                    HStack(spacing: 8) {
                        Image(systemName: pairing.readOnly == true ? "eye" : "iphone")
                            .foregroundStyle(Cypher.dim)
                        Text(pairing.label)
                            .font(Cypher.mono(11, weight: .semibold))
                        Text(pairing.lastSeen.map { "last seen \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "not used yet")
                            .font(Cypher.mono(10.5))
                            .foregroundStyle(Cypher.dim)
                        Spacer()
                        Button("Remove") { nostr.unpair(pairing) }
                    }
                }
            }
        }
    }

    private func nostrPairingView(link: String, readOnly: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: link.qrQode)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .background(Color.white)
            VStack(alignment: .leading, spacing: 8) {
                Text("In Plasma: Node Manager → + → scan this code.")
                    .font(Cypher.mono(11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Label(readOnly ? "Read-only pairing" : "Full access pairing: it can spend. Only scan it with your own phone.",
                      systemImage: readOnly ? "eye" : "exclamationmark.shield.fill")
                    .font(Cypher.mono(11, weight: .semibold))
                    .foregroundStyle(readOnly ? palette.accent : Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The code holds the pairing's key: it's shown once. Pair again for another phone.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        copy(link, id: "nostr-link")
                    } label: {
                        Image(systemName: copied == "nostr-link" ? "checkmark" : "link")
                        Text("Copy link")
                    }
                    if LightningNode.plasmaInstalledOnMac, let url = URL(string: link) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "macbook")
                            Text("Open in Plasma")
                        }
                    }
                    Button("Done") { node.hideConnection() }
                }
            }
        }
        .task(id: link) {
            try? await Task.sleep(for: .seconds(180))
            if node.plasmaNostr?.link == link { node.hideConnection() }
        }
    }

    @ViewBuilder
    private var firewallNote: some View {
        if node.acceptPeersOnNetwork, let command = node.firewallCommand {
            VStack(alignment: .leading, spacing: 8) {
                Label("The macOS firewall blocks incoming peers", systemImage: "flame")
                    .font(Cypher.mono(12, weight: .bold))
                    .foregroundStyle(Cypher.amber)
                Text("The firewall is on and doesn't allow incoming connections to this Core Lightning's lightning_connectd, so Lightning peers can't connect in. Homebrew's binaries aren't allowed automatically, and every update needs a new rule. Run this in Terminal (it asks for your password), or add the file in System Settings → Network → Firewall → Options:")
                    .font(Cypher.mono(11))
                    .fixedSize(horizontal: false, vertical: true)
                Text(command)
                    .font(Cypher.mono(10))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Cypher.bg)
                HStack(spacing: 8) {
                    Button {
                        copy(command, id: "firewall")
                    } label: {
                        Image(systemName: copied == "firewall" ? "checkmark" : "doc.on.doc")
                        Text("Copy command")
                    }
                    Button("Open Firewall settings") { node.openFirewallSettings() }
                    Button("Check again") { node.checkFirewall() }
                }
            }
            .padding(10)
            .background(Cypher.bg.opacity(0.5))
            .overlay(Rectangle().stroke(Cypher.amber.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: - Connect

    private var connectCard: some View {
        GroupBox("Other wallets · CLNRest over Tor") {
            VStack(alignment: .leading, spacing: 12) {
                Text("For Lightning wallets that support CLNRest (Zeus, for example). They connect over Tor to this node's onion address with a rune, a key Core Lightning issues and can revoke.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = node.restUnavailable {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let connection = node.connection {
                    connectionView(connection)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            node.connectWallet(readOnly: false)
                        } label: {
                            Image(systemName: "qrcode")
                            Text("Full access")
                        }
                        .buttonStyle(.cypherProminent)
                        .disabled(node.restUnavailable != nil)
                        .help("A rune that can do anything, including send payments")
                        Button {
                            node.connectWallet(readOnly: true)
                        } label: {
                            Image(systemName: "eye")
                            Text("Read-only")
                        }
                        .disabled(node.restUnavailable != nil)
                        .help("A rune that can only view: balances, channels, invoices")
                        Spacer()
                        Button {
                            confirmRevoke = true
                        } label: {
                            Image(systemName: "xmark.shield")
                            Text("Revoke all runes")
                        }
                    }
                }
            }
        }
    }

    private func connectionView(_ connection: LightningNode.Connection) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: connection.url.qrQode)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .background(Color.white)
            VStack(alignment: .leading, spacing: 8) {
                Label(connection.readOnly ? "Read-only rune" : "Full access rune: it can spend. Only scan it with your own wallet.",
                      systemImage: connection.readOnly ? "eye" : "exclamationmark.shield.fill")
                    .font(Cypher.mono(11, weight: .semibold))
                    .foregroundStyle(connection.readOnly ? palette.accent : Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
                field("Host", connection.host, id: "host")
                field("Port", "\(connection.port)", id: "port")
                field("Rune", connection.rune, id: "rune")
                HStack(spacing: 8) {
                    Button {
                        copy(connection.url, id: "url")
                    } label: {
                        Image(systemName: copied == "url" ? "checkmark" : "link")
                        Text("Copy clnrest URL")
                    }
                    Button("Hide") { node.hideConnection() }
                }
            }
        }
        .task(id: connection.rune) {
            // Don't leave a rune on screen.
            try? await Task.sleep(for: .seconds(120))
            if node.connection?.rune == connection.rune { node.hideConnection() }
        }
    }

    private func field(_ label: String, _ value: String, id: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(Cypher.mono(9.5, weight: .bold))
                .foregroundStyle(Cypher.dim)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(Cypher.mono(10.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                copy(value, id: id)
            } label: {
                Image(systemName: copied == id ? "checkmark" : "doc.on.doc")
            }
        }
    }

    // MARK: - Settings and log

    private var settingsCard: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $node.acceptPeersOnNetwork) {
                    Text("Accept incoming peer connections")
                }
                .toggleStyle(.switch)
                Text("Listens on port \(String(node.peerPort)) on all of this Mac's addresses, so other Lightning nodes on your network or VPN (or anywhere, through a forwarded port) can connect in. Off: only outgoing connections. Plasma doesn't need this: it uses Nostr Connect. Takes effect the next time Core Lightning starts.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
                firewallNote
                Toggle(isOn: $node.peersOverTor) {
                    Text("Connect to peers only through Tor")
                }
                .toggleStyle(.switch)
                Text("Hides this Mac's IP address from Lightning peers. Some peers are only reachable over clearnet; turn this off to reach them. Takes effect the next time Core Lightning starts.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if let pruning = node.pruning, pruning.stuckAt == nil {
                    Text("Your Bitcoin node is pruned: it keeps about \(NodeView.duration(pruning.window)) of blocks. Don't leave Core Lightning stopped longer than that, or it can't catch up (it needs every block since it last ran).")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Back up \(node.hsmSecretPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")): it holds the keys to this node's on-chain funds. Channel funds also need the node's database (or emergency.recover) to recover.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
                nodeDataSection
                HStack(spacing: 8) {
                    Button {
                        node.openConfig()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                        Text("My options")
                    }
                    .help("~/.lightning/<network>/config: your own lightningd options")
                    Button {
                        node.showNodeFolder()
                    } label: {
                        Image(systemName: "folder")
                        Text("Show node folder")
                    }
                    Button {
                        node.openLog()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Open log")
                    }
                }
            }
        }
    }

    private var nodeDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(NodeMonitor.networkName(node.chain)) node: \(node.hasExistingNode ? node.networkDir.replacingOccurrences(of: NSHomeDirectory(), with: "~") : "not created yet")")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                Spacer()
                if node.hasExistingNode {
                    Button {
                        confirmFreshNode = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle")
                        Text("Start a new node…")
                    }
                    .disabled(node.phase == .stopping)
                }
            }
            ForEach(node.keptOldNodes, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(Cypher.dim)
                    Text("Kept: \((path as NSString).lastPathComponent)")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                    Spacer()
                    Button("Delete") { deleteKept = path }
                }
            }
        }
        .confirmationDialog("Delete \((deleteKept as NSString?)?.lastPathComponent ?? "")?", isPresented: Binding(
            get: { deleteKept != nil }, set: { if !$0 { deleteKept = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let path = deleteKept { node.deleteKeptNode(path) }
                deleteKept = nil
            }
            Button("Cancel", role: .cancel) { deleteKept = nil }
        } message: {
            Text(node.chain == "main"
                 ? "Its hsm_secret and database are erased for good: any funds it still has are lost unless you have a backup."
                 : "It's removed for good (test coins only).")
        }
    }

    private var logCard: some View {
        GroupBox("Log") {
            if node.logTail.isEmpty {
                Text("No log yet for \(NodeMonitor.networkName(node.chain)).")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(node.logTail.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(Cypher.mono(10.5))
                            .foregroundStyle(line.contains("**BROKEN**") || line.contains("UNUSUAL") ? Cypher.amber
                                             : index == node.logTail.count - 1 ? palette.text : palette.dim)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding(8)
                .background(Cypher.bg)
            }
        }
    }

    // MARK: - Helpers

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copied == id { copied = nil }
        }
    }

    static func sats(_ value: Int) -> String {
        "\(value.withCommas) sats"
    }
}

private extension LightningNode.Phase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

private extension Color {
    /// "rrggbb" (a node's color in getinfo).
    init?(hex: String) {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

private struct LNTile: View {
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
                .foregroundStyle(valueColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(Cypher.text))
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

/// Sidebar status, like the other services: a check while lightningd runs on the current
/// network, a spinner while it starts or stops, an x when it's installed but stopped, and a
/// download arrow when it isn't installed yet.
struct LightningSidebarIcon: View {
    @ObservedObject private var node = LightningNode.shared
    @State private var running = false
    @State private var installed = LightningNode.prefix != nil
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if running {
                Image(systemName: "checkmark")
                    .foregroundStyle(Cypher.accent)
                    .help("Core Lightning is running")
            } else if node.phase.isTransitioning && node.phase != .unknown {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
                    .help(node.phase == .stopping ? "Core Lightning is stopping" : "Core Lightning is starting")
            } else if installed {
                Image(systemName: "xmark")
                    .foregroundStyle(Cypher.dim)
                    .help("Core Lightning is stopped")
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Cypher.dim)
                    .help("Core Lightning isn't installed yet")
            }
        }
        .onAppear { check() }
        .onReceive(timer) { _ in check() }
        .onChange(of: node.phase) { check() }
        .onChange(of: node.install) { check() }
    }

    private func check() {
        let network = LightningNode.network(chain: UserDefaults.standard.string(forKey: "chain") ?? "main")
        running = LightningNode.isRunning(network: network)
        installed = LightningNode.prefix != nil
    }
}
