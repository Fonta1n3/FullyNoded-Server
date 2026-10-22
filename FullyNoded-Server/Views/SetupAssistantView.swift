//
//  SetupAssistantView.swift
//  FullyNoded-Server
//
//  First-run Setup Assistant: welcome → check this Mac → configure the node → install →
//  start → connect Fully Noded. Opens by itself until it's finished or skipped (when no
//  node is installed yet), and again from Help or the app menu.
//

import SwiftUI

struct SetupAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SetupAssistant()
    /// Called after Finish / Skip, so the main window can pick up the new settings.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepRail(current: model.step)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            Rectangle().fill(Cypher.line).frame(height: 1)

            ScrollView {
                Group {
                    switch model.step {
                    case .welcome: WelcomeStep(model: model)
                    case .check: CheckStep(model: model)
                    case .configure: ConfigureStep(model: model)
                    case .install: InstallStep(model: model, installer: model.installer)
                    case .start: StartStep(model: model)
                    case .connect: ConnectStep()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Rectangle().fill(Cypher.line).frame(height: 1)
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 780, height: 620)
        .background(Cypher.bg)
        .buttonStyle(.cypher)
        .groupBoxStyle(CypherGroupBoxStyle())
        .onAppear {
            model.runChecks()
        }
        .onChange(of: model.step) { oldStep, newStep in
            if oldStep == .start { model.stopFollowingNode() }
            if newStep == .start { model.followNode() }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.step != .welcome {
                Button("Back") { go(-1) }
                    .disabled(model.installer.isBusy)
            }
            Spacer()
            if model.step != .connect {
                Button("Skip setup") { close() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Cypher.dim)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.installer.isBusy)
            }
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.cypherProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: return "Get started"
        case .configure: return "Save and continue"
        case .install: return model.installedEnv == nil ? "Install first" : "Continue"
        case .connect: return "Finish"
        default: return "Continue"
        }
    }

    private var canContinue: Bool {
        switch model.step {
        case .install: return model.installedEnv != nil && !model.installer.isBusy
        default: return true
        }
    }

    private func primaryAction() {
        switch model.step {
        case .configure:
            model.applyConfiguration()
            go(1)
        case .connect:
            close()
        default:
            go(1)
        }
    }

    private func go(_ offset: Int) {
        guard let next = SetupAssistant.Step(rawValue: model.step.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { model.step = next }
    }

    private func close() {
        model.finish()
        onFinish()
        dismiss()
    }
}

// MARK: - Step rail

private struct StepRail: View {
    let current: SetupAssistant.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SetupAssistant.Step.allCases) { step in
                let done = step.rawValue < current.rawValue
                let active = step == current
                HStack(spacing: 6) {
                    Text(done ? "✓" : String(format: "%02d", step.rawValue + 1))
                        .font(Cypher.mono(11, weight: .bold))
                    Text(step.title.uppercased())
                        .font(Cypher.mono(11, weight: active ? .bold : .regular))
                }
                .foregroundStyle(active ? Cypher.bg : (done ? Cypher.accent : Cypher.dim))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Rectangle().fill(active ? Cypher.accent : Color.clear))
                .overlay(Rectangle().stroke(active ? Cypher.accent : Cypher.line.opacity(done ? 1 : 0.4), lineWidth: 1))
                if step != SetupAssistant.Step.allCases.last {
                    Rectangle()
                        .fill(done ? Cypher.accent : Cypher.line.opacity(0.4))
                        .frame(height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(SetupAssistant.Step.allCases.count): \(current.title)")
    }
}

// MARK: - Shared pieces

private struct StepHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Cypher.mono(20, weight: .bold))
                .foregroundStyle(Cypher.text)
            Text(detail)
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

/// A status line: coloured dot, label, value and an optional trailing view.
private struct StatusRow<Trailing: View>: View {
    let color: Color
    let label: String
    let value: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Cypher.mono(12, weight: .semibold))
                .frame(width: 170, alignment: .leading)
            Text(value)
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension StatusRow where Trailing == EmptyView {
    init(color: Color, label: String, value: String) {
        self.init(color: color, label: label, value: value) { EmptyView() }
    }
}

/// A selectable row: radio mark, title and explanation.
private struct ChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Cypher.accent : Cypher.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Cypher.mono(12, weight: .semibold))
                        .foregroundStyle(Cypher.text)
                    Text(detail)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private func gigabytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    return gb >= 10 ? "\(Int(gb.rounded())) GB" : String(format: "%.1f GB", gb)
}

// MARK: - 1 Welcome

private struct WelcomeStep: View {
    @ObservedObject var model: SetupAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                StepHeader(title: "Run your own Bitcoin node",
                           detail: "Fully Noded Server installs and runs a Bitcoin node on this Mac, and connects your Fully Noded wallet to it.")
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("arrow.down.circle", "Bitcoin Core or Bitcoin Knots",
                        "Downloaded from the project's own site and checked against its published SHA-256 hashes. Nothing to compile.")
                feature("lock.shield", "Private by default",
                        "FN-Server runs Tor, so your node gets an onion address and your wallet never needs a third-party server.")
                feature("iphone.and.arrow.forward", "Connect Fully Noded",
                        "Over Tor from anywhere, or Nostr Connect for a faster connection at home or over a VPN.")
            }
            .cypherPanel(padding: 16)

            Text("Setup takes a few minutes. After that the node downloads and checks the blockchain in the background, which can take from a few hours to a few days.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)

            if let env = model.installedEnv {
                Label("\(model.implementation.name) \(env.version) is already installed. You can review its settings, or skip setup.",
                      systemImage: "checkmark.circle")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.accent)
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Cypher.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Cypher.mono(12, weight: .semibold))
                Text(detail)
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 2 Check

private struct CheckStep: View {
    @ObservedObject var model: SetupAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Check this Mac",
                       detail: "Nothing here blocks setup. Items marked optional are only needed for JoinMarket.")

            GroupBox("This Mac") {
                VStack(alignment: .leading, spacing: 10) {
                    StatusRow(color: Cypher.accent, label: "Processor",
                              value: NodeImplementation.arch == "arm64" ? "Apple silicon" : "Intel")
                    StatusRow(color: Cypher.accent, label: "Memory",
                              value: "\(gigabytes(model.memoryBytes)) · half is used to speed up the first sync")
                    freeSpaceRow
                }
            }

            GroupBox("Privacy") {
                torRow
            }

            GroupBox("Optional · JoinMarket") {
                VStack(alignment: .leading, spacing: 10) {
                    toolRow(label: "Command Line Tools", installed: model.hasCommandLineTools,
                            note: "git, used to install JoinMarket", install: model.installCommandLineTools)
                    toolRow(label: "Homebrew", installed: model.hasHomebrew,
                            note: "JoinMarket's dependencies", install: model.installHomebrew)
                }
            }
        }
    }

    private var freeSpaceRow: some View {
        let free = model.freeBytes
        let color: Color = free.map { $0 > 100_000_000_000 ? Cypher.accent : Cypher.amber } ?? Cypher.dim
        return StatusRow(color: color, label: "Free space",
                         value: free.map { "\(gigabytes($0)) on the data folder's drive" } ?? "checking…")
    }

    private var torRow: some View {
        let (color, value): (Color, String) = {
            switch model.torState {
            case .connected: return (Cypher.accent, "Connected")
            case .started, .refreshing: return (Cypher.amber, "Connecting… (keeps going in the background)")
            case .stopped: return (Cypher.danger, "Stopped · start it from the Tor page")
            case .none: return (Cypher.amber, "Starting…")
            }
        }()
        return StatusRow(color: color, label: "Tor", value: value)
    }

    private func toolRow(label: String, installed: Bool?, note: String, install: @escaping () -> Void) -> some View {
        StatusRow(color: installed == true ? Cypher.accent : Cypher.dim,
                  label: label,
                  value: installed == nil ? "checking…" : (installed! ? "Installed" : "Not installed · \(note)")) {
            if installed == false {
                Button("Install…", action: install)
            }
        }
    }
}

// MARK: - 3 Configure

private struct ConfigureStep: View {
    @ObservedObject var model: SetupAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Configure your node",
                       detail: "You can change the network and implementation later from the node's page and Settings.")

            GroupBox("Implementation") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $model.implementation) {
                        ForEach(NodeImplementation.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    Text(model.implementation == .core
                         ? "The reference implementation of Bitcoin."
                         : "A derivative of Bitcoin Core with additional options and its own default policies.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                }
            }
            .onChange(of: model.implementation) { _, implementation in
                if !implementation.chains.contains(model.chain) { model.chain = "main" }
                model.refreshInstall()
            }

            GroupBox("Network") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.implementation.chains, id: \.self) { chain in
                        ChoiceRow(title: SetupAssistant.networkName(chain),
                                  detail: SetupAssistant.networkDetail(chain),
                                  selected: model.chain == chain) { model.chain = chain }
                    }
                }
            }

            GroupBox("Storage") {
                if let conf = model.existingConf {
                    existingConfNote(conf)
                } else {
                    storageChoice
                }
            }

            GroupBox("Data folder") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.dataDir)
                            .font(Cypher.mono(12))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change…") { model.chooseDataDir() }
                    }
                    Text("Use an external drive if this Mac is short on space, and keep it connected while the node runs.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    private var storageChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChoiceRow(title: "Pruned", detail: "Validates everything but keeps only the most recent blocks, so it needs little disk space. Wallets with history older than those blocks can't be rescanned.",
                      selected: model.storage == .pruned) { model.storage = .pruned }
            if model.storage == .pruned {
                HStack(spacing: 10) {
                    Slider(value: $model.pruneGB, in: 1...200, step: 1)
                        .frame(width: 260)
                    Text("\(Int(model.pruneGB)) GB of blocks")
                        .font(Cypher.mono(12))
                }
                .padding(.leading, 28)
            }
            ChoiceRow(title: "Full", detail: "Keeps the whole blockchain and a transaction index. About \(SetupAssistant.fullSizeGB(chain: model.chain)) GB on \(SetupAssistant.networkName(model.chain)).",
                      selected: model.storage == .full) { model.storage = .full }
            spaceHint
        }
    }

    private var spaceHint: some View {
        let needed = model.requiredBytes
        let free = model.freeBytes
        let enough = free.map { $0 >= needed } ?? true
        return Label("Needs about \(gigabytes(needed))" + (free.map { " · \(gigabytes($0)) free" } ?? ""),
                     systemImage: enough ? "internaldrive" : "exclamationmark.triangle")
            .font(Cypher.mono(11))
            .foregroundStyle(enough ? Cypher.dim : Cypher.amber)
            .padding(.top, 4)
    }

    private func existingConfNote(_ conf: (prune: Int?, txindex: Int?)) -> some View {
        let prune = conf.prune ?? 0
        let mode = prune == 0 ? "full (no pruning)" : (prune == 1 ? "manual pruning" : "pruned to \(Int((Double(prune) / 953.674).rounded())) GB")
        return VStack(alignment: .leading, spacing: 6) {
            Label("This folder already has a bitcoin.conf: \(mode), txindex=\(conf.txindex ?? 0).", systemImage: "doc.text")
                .font(Cypher.mono(12))
            Text("FN-Server keeps those settings and only adds its own RPC login. Edit bitcoin.conf from the node's Utilities to change them.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 4 Install

private struct InstallStep: View {
    @ObservedObject var model: SetupAssistant
    @ObservedObject var installer: NodeInstaller
    @State private var selection: TaggedReleaseElement?
    @State private var fetchedFor: NodeImplementation?
    @State private var reinstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Install \(model.implementation.name)",
                       detail: "Downloaded straight from \(model.implementation == .core ? "bitcoincore.org" : "bitcoinknots.org") and checked against the release's SHA256SUMS before it's unpacked.")

            if let env = model.installedEnv, !reinstall, !installer.isBusy {
                GroupBox("Installed") {
                    HStack {
                        StatusRow(color: Cypher.accent, label: model.implementation.name, value: "v\(env.version)")
                        Button("Install another version") { reinstall = true }
                    }
                }
            } else {
                releasePicker
                progress
            }
        }
        .onAppear(perform: fetchIfNeeded)
        .onChange(of: installer.stage) { _, stage in
            if case .installed = stage {
                reinstall = false
                model.refreshInstall()
            }
        }
    }

    private func fetchIfNeeded() {
        guard fetchedFor != model.implementation else { return }
        fetchedFor = model.implementation
        selection = nil
        installer.fetchReleases(for: model.implementation)
    }

    @ViewBuilder
    private var releasePicker: some View {
        GroupBox("Version") {
            VStack(alignment: .leading, spacing: 10) {
                if installer.isFetchingReleases {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                        Text("Fetching releases from GitHub…").font(Cypher.mono(12)).foregroundStyle(Cypher.dim)
                    }
                } else if let error = installer.releasesError {
                    Text(error).font(Cypher.mono(12)).foregroundStyle(Cypher.danger)
                    Button("Try again") {
                        fetchedFor = nil
                        fetchIfNeeded()
                    }
                } else {
                    let releases = Array(installer.releases.prefix(12))
                    let chosen = selection ?? releases.first
                    Picker("Release", selection: Binding(get: { chosen }, set: { selection = $0 })) {
                        ForEach(releases, id: \.self) { release in
                            Text((release.tagName ?? "") + (release.prerelease == true ? " (release candidate)" : ""))
                                .tag(Optional(release))
                        }
                    }
                    .frame(width: 360)
                    .disabled(installer.isBusy)

                    if let chosen, let url = NodeInstaller.tarballURL(for: chosen, implementation: model.implementation) {
                        Text(verbatim: url)
                            .font(Cypher.mono(11))
                            .foregroundStyle(Cypher.dim)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            Button("Install \(chosen.tagName ?? "")") {
                                installer.install(chosen, implementation: model.implementation)
                            }
                            .buttonStyle(.cypherProminent)
                            .disabled(installer.isBusy)
                            if let notes = releaseNotesURL(chosen) {
                                Link("Release notes", destination: notes).font(Cypher.mono(12))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch installer.stage {
        case .idle, .installed:
            EmptyView()
        case .preparing:
            stageRow(spinner: true, "Writing bitcoin.conf…")
        case .downloading(let file, let fraction):
            GroupBox("Downloading") {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    Text("\(file) · \(Int(fraction * 100))%").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
            }
        case .verifying:
            GroupBox("Verifying in Terminal") {
                VStack(alignment: .leading, spacing: 8) {
                    stageRow(spinner: true, "Waiting for the installer…")
                    Text("A Terminal window opened. It compares the download's SHA-256 with SHA256SUMS, unpacks it and signs the binaries for this Mac. Close Terminal when it says \"Installation complete\". This page continues by itself.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel") { installer.cancelVerification() }
                }
            }
        case .failed(let message):
            GroupBox("Install failed") {
                Text(message)
                    .font(Cypher.mono(12))
                    .foregroundStyle(Cypher.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stageRow(spinner: Bool, _ text: String) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().scaleEffect(0.5).frame(width: 16, height: 16) }
            Text(text).font(Cypher.mono(12))
        }
    }

    private func releaseNotesURL(_ release: TaggedReleaseElement) -> URL? {
        guard let tag = release.tagName else { return nil }
        switch model.implementation {
        case .core:
            return URL(string: "https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-\(tag.replacingOccurrences(of: "v", with: "")).md")
        case .knots:
            return URL(string: "https://github.com/bitcoinknots/bitcoin/blob/\(tag)/doc/release-notes.md")
        }
    }
}

// MARK: - 5 Start

private struct StartStep: View {
    @ObservedObject var model: SetupAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Start your node",
                       detail: "\(model.implementation.name) runs in the background on \(SetupAssistant.networkName(model.chain)). It keeps running if you close FN-Server.")

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow
                    if let info = model.blockchainInfo, model.nodeStatus == .running {
                        syncProgress(info)
                    }
                }
            }

            Text("The first sync downloads and checks every block. Depending on your Mac and connection it takes a few hours (test networks) to a few days (mainnet). You can connect Fully Noded meanwhile; balances appear once it's synced.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusRow: some View {
        let (color, value): (Color, String) = {
            switch model.nodeStatus {
            case .unknown: return (Cypher.dim, "Checking…")
            case .stopped: return (Cypher.danger, "Stopped")
            case .starting(let message): return (Cypher.amber, message)
            case .running: return (Cypher.accent, "Running")
            case .failed(let message): return (Cypher.danger, message)
            }
        }()
        return StatusRow(color: color, label: model.implementation.name, value: value) {
            switch model.nodeStatus {
            case .stopped, .failed:
                Button("Start") { model.startNode() }
                    .buttonStyle(.cypherProminent)
                    .disabled(model.installedEnv == nil)
            case .starting:
                ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
            default:
                EmptyView()
            }
        }
    }

    private func syncProgress(_ info: BlockchainInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: info.verificationprogress)
            Text(info.initialblockdownload
                 ? "Syncing · block \(info.blocks) · \(String(format: "%.2f", info.verificationprogress * 100))% verified"
                 : "Synced · block \(info.blocks)")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
        }
    }
}

// MARK: - 6 Connect

private struct ConnectStep: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Connect Fully Noded",
                       detail: "Pick one or both. You can come back to either from the sidebar at any time.")

            HStack(alignment: .top, spacing: 16) {
                option(title: "Nostr Connect",
                       icon: "bolt.horizontal",
                       badge: "FAST",
                       lines: ["Your node loads in about a second: no Tor circuit to build.",
                               "Fully Noded encrypts each call for this Mac (NIP-44) and sends it as a short-lived nostr message through a relay. FN-Server answers from your node the same way. The relay only sees ciphertext, and only paired phones can use your node.",
                               "Use this Mac's relay at home or over a VPN like Tailscale, or a public relay from anywhere."],
                       button: "Set up Nostr Connect") { openWindow(id: "NostrConnect") }

                option(title: "Tor · Quick Connect",
                       icon: "network.badge.shield.half.filled",
                       badge: nil,
                       lines: ["Works from anywhere, through your node's onion address. Slower to connect.",
                               "In Fully Noded: Node Manager → + → Scan QR, then authorize its RPC user here."],
                       button: "Show Quick Connect QR") { openWindow(id: "QuickConnect") }
            }

            Text("Don't have Fully Noded yet? Find it in the App Store, or under Help → Download Links.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
        }
    }

    private func option(title: String, icon: String, badge: String?, lines: [String], button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(Cypher.mono(13, weight: .bold))
                    .foregroundStyle(Cypher.accent)
                if let badge {
                    Text(badge)
                        .font(Cypher.mono(9, weight: .bold))
                        .foregroundStyle(Cypher.bg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Rectangle().fill(Cypher.accent))
                }
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(button, action: action)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .cypherPanel(padding: 16)
    }
}
