//
//  TorView.swift
//  FullyNoded-Server
//
//  The Tor page: the built-in tor's status with stop / start and new circuits, the onion
//  services it publishes, its torrc and its log.
//

import SwiftUI
import AppKit

/// Mirrors TorClient for the page (TorClient isn't observable).
final class TorModel: ObservableObject {
    enum Phase: Equatable {
        case starting(Int)
        case connected
        case stopped
        case failed(String)
    }

    struct Service: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let port: Int
        let hostname: String?
        /// The Bitcoin RPC service of the network in use.
        let inUse: Bool
    }

    @Published private(set) var phase: Phase = .starting(0)
    @Published private(set) var version: String?
    @Published private(set) var services: [Service] = []
    @Published private(set) var busy = false
    @Published var notice: String?
    private var timer: Timer?

    func appear() {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func disappear() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let tor = TorClient.sharedInstance
        let phase: Phase
        switch tor.state {
        case .connected, .refreshing: phase = .connected
        case .stopped: phase = .stopped
        case .started: phase = .starting(tor.progress)
        case .none: phase = tor.lastError.map { .failed($0) } ?? .starting(tor.progress)
        }
        if phase != self.phase { self.phase = phase }
        if version != tor.version { version = tor.version }
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        let inUse = TorClient.OnionService.bitcoin(chain: chain)
        let services = TorClient.OnionService.allCases.map {
            Service(title: $0.title, port: $0.port, hostname: tor.hostname(for: $0), inUse: $0 == inUse)
        }
        if services != self.services { self.services = services }
    }

    func start() {
        busy = true
        let tor = TorClient.sharedInstance
        if tor.isPaused {
            tor.resume { [weak self] _ in self?.busy = false; self?.refresh() }
        } else {
            tor.start(delegate: nil)
            busy = false
            refresh()
        }
    }

    func stop() {
        busy = true
        TorClient.sharedInstance.pause { [weak self] success in
            self?.busy = false
            if !success { self?.notice = TorClient.sharedInstance.lastError ?? "Couldn't stop tor." }
            self?.refresh()
        }
    }

    func newCircuits() {
        busy = true
        TorClient.sharedInstance.newCircuits { [weak self] success in
            self?.busy = false
            self?.notice = success
                ? "New circuits: new connections go through new tor paths, and the torrc was reloaded."
                : "Couldn't ask tor for new circuits."
        }
    }
}

struct TorView: View {
    @StateObject private var model = TorModel()
    @State private var showTorrc = false
    @State private var confirmStop = false
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                servicesCard
                filesCard
                logCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 480)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .alert(model.notice ?? "", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .alert("Stop Tor?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { model.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fully Noded can't reach this node over Tor, and JoinMarket loses its onion connections, until Tor is started again. Nostr Connect keeps working.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("Tor")
                    .font(Cypher.mono(20, weight: .bold))
                if let version = model.version {
                    Text("v\(version)")
                        .font(Cypher.mono(12))
                        .foregroundStyle(Cypher.dim)
                }
                Spacer()
            }
            Text("Built into this app. It publishes your node's RPC and JoinMarket as onion services, so Fully Noded can reach them from anywhere without opening a port or revealing this Mac's IP address.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        GroupBox("Status") {
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
                    if model.busy {
                        ProgressView().controlSize(.small)
                    }
                    switch model.phase {
                    case .connected:
                        Button {
                            model.newCircuits()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("New circuits")
                        }
                        .help("New tor paths for new connections; also reloads the torrc")
                        .disabled(model.busy)
                        Button {
                            confirmStop = true
                        } label: {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .disabled(model.busy)
                    case .stopped:
                        Button {
                            model.start()
                        } label: {
                            Image(systemName: "play.fill")
                            Text("Start")
                        }
                        .buttonStyle(.cypherProminent)
                        .disabled(model.busy)
                    case .starting:
                        Button {
                            confirmStop = true
                        } label: {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .disabled(model.busy || !TorClient.sharedInstance.canPause)
                    case .failed:
                        EmptyView()
                    }
                }
                if case .starting(let progress) = model.phase {
                    ProgressView(value: Double(min(max(progress, 0), 100)), total: 100)
                        .tint(Cypher.accent)
                }
                if case .failed = model.phase {
                    Text("Quit and reopen Fully Noded Server to start Tor again. If it keeps failing, the log below says why.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .connected: return Cypher.accent
        case .starting: return Cypher.amber
        case .stopped, .failed: return Cypher.danger
        }
    }

    private var statusTitle: String {
        switch model.phase {
        case .connected: return "Connected"
        case .starting(let progress): return "Bootstrapping \(progress)%"
        case .stopped: return "Stopped"
        case .failed: return "Not running"
        }
    }

    private var statusDetail: String {
        switch model.phase {
        case .connected: return "Onion services are reachable. SOCKS proxy on 127.0.0.1:\(TorClient.socksPort)."
        case .starting: return "Building circuits to the tor network. Usually under a minute."
        case .stopped: return "Offline: no circuits, and the onion services below can't be reached."
        case .failed(let reason): return reason
        }
    }

    // MARK: - Onion services

    private var servicesCard: some View {
        GroupBox("Onion services") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.services) { service in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(service.title)
                                    .font(Cypher.mono(12, weight: .semibold))
                                if service.inUse {
                                    Text("IN USE")
                                        .font(Cypher.mono(9, weight: .bold))
                                        .foregroundStyle(Cypher.bg)
                                        .padding(.horizontal, 4)
                                        .background(Cypher.accent)
                                }
                            }
                            Text(service.hostname.map { "\($0):\(service.port)" } ?? "Not created yet (tor creates it on its first start).")
                                .font(Cypher.mono(10.5))
                                .foregroundStyle(Cypher.dim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if let hostname = service.hostname {
                            Button {
                                copy("\(hostname):\(service.port)", id: service.id)
                            } label: {
                                Image(systemName: copied == service.id ? "checkmark" : "doc.on.doc")
                            }
                            .help("Copy the onion address")
                        }
                    }
                    if service.id != model.services.last?.id {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
                Text("Each address only answers on its port, and the RPC still needs your rpc credentials. Use Quick Connect on the node's page to pair Fully Noded.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Files and log

    private var filesCard: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation { showTorrc.toggle() }
                    } label: {
                        Image(systemName: "doc.plaintext")
                        Text(showTorrc ? "Hide torrc" : "Show torrc")
                    }
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Torrc.torPath())
                    } label: {
                        Image(systemName: "folder")
                        Text("Open Tor folder")
                    }
                }
                if showTorrc {
                    ConfigTextView(configString: Torrc.torrc, title: "Torrc", contentType: .plain)
                        .frame(minHeight: 240)
                }
            }
        }
    }

    private var logCard: some View {
        GroupBox("notices.log") {
            TorLogView()
                .frame(height: 260)
                .background(Cypher.bg)
        }
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copied == id { copied = nil }
        }
    }
}
