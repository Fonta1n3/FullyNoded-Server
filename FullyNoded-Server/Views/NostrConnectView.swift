//
//  NostrConnectView.swift
//  FullyNoded-Server
//
//  The Nostr Connect page: run the relay, add public relays, pair Fully Noded devices.
//

import SwiftUI
import Combine

/// Settings and live state for Nostr Connect. Starts the relay and bridge at launch when enabled.
final class NostrConnectModel: ObservableObject {
    static let shared = NostrConnectModel()

    @Published var relayEnabled: Bool { didSet { UserDefaults.standard.set(relayEnabled, forKey: Self.enabledKey) } }
    @Published var port: UInt16 { didSet { UserDefaults.standard.set(Int(port), forKey: Self.portKey) } }
    @Published var extraRelays: [String] { didSet { UserDefaults.standard.set(extraRelays, forKey: Self.extraKey) } }
    @Published private(set) var vpnAddresses: [String] = []
    @Published private(set) var relayStatus = NostrRelay.shared.status()
    @Published private(set) var relayStates: [String: NostrBridge.RelayState] = [:]
    @Published private(set) var pairings: [NostrBridge.Pairing] = []
    @Published private(set) var lanAddresses: [String] = []
    @Published var alertMessage: String?
    /// The relay serves wss:// with its pinned self-signed certificate (RelayTLS).
    @Published private(set) var useTLS: Bool { didSet { UserDefaults.standard.set(useTLS, forKey: Self.tlsKey) } }
    /// SHA-256 of the relay's certificate, once loaded.
    @Published private(set) var certFingerprint: String?
    private var tlsIdentity: SecIdentity?

    private static let enabledKey = "nostrConnectRelayEnabled"
    private static let portKey = "nostrConnectRelayPort"
    private static let extraKey = "nostrConnectExtraRelays"
    /// Outside addresses from before Tailscale Funnel replaced them (cleared at launch).
    private static let outsideKey = "nostrConnectOutsideURLs"
    private static let tlsKey = "nostrConnectRelayTLS"
    /// Set once the default public relays have been added (so a removed one stays removed).
    private static let defaultRelaysKey = "nostrConnectDefaultRelaysAdded"
    static let defaultPort: UInt16 = 7777
    /// Public relays included by default, so a pairing still works when this Mac's relay can't be
    /// reached from outside (Tailscale Funnel's ingress has been seen to stop forwarding). Each
    /// accepts the ~40 KB RPC frames with no auth or payment; they only see ciphertext.
    static let defaultPublicRelays = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"]

    private init() {
        relayEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        port = (1024...65535).contains(stored) ? UInt16(stored) : Self.defaultPort
        var relays = UserDefaults.standard.stringArray(forKey: Self.extraKey) ?? []
        if !UserDefaults.standard.bool(forKey: Self.defaultRelaysKey) {
            relays += Self.defaultPublicRelays.filter { !relays.contains($0) }
            UserDefaults.standard.set(relays, forKey: Self.extraKey)
            UserDefaults.standard.set(true, forKey: Self.defaultRelaysKey)
        }
        extraRelays = relays
        UserDefaults.standard.removeObject(forKey: Self.outsideKey)
        // wss:// by default for a new setup; existing ws:// pairings keep working until changed.
        if let stored = UserDefaults.standard.object(forKey: Self.tlsKey) as? Bool {
            useTLS = stored && RelayTLS.isSupported
        } else {
            useTLS = RelayTLS.isSupported && NostrBridge.shared.allPairings.isEmpty
        }
        NostrRelay.shared.allowedAuthors = { NostrBridge.shared.pairedPublicKeys }
        NostrRelay.shared.onChange = { [weak self] in self?.refresh() }
        NostrBridge.shared.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    /// At launch: bring up whatever was on before.
    func startIfConfigured() {
        apply()
        TailscaleFunnel.shared.startMonitoring()
    }

    func refresh() {
        relayStatus = NostrRelay.shared.status()
        relayStates = NostrBridge.shared.states()
        pairings = NostrBridge.shared.allPairings
        lanAddresses = NostrRelay.lanAddresses()
        vpnAddresses = NostrRelay.vpnAddresses()
    }

    /// Starts or stops the relay and points the bridge at the relays in use.
    func apply() {
        if relayEnabled {
            // wss: load (or create, once) the relay's certificate first.
            if useTLS && tlsIdentity == nil {
                RelayTLS.load { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let loaded):
                        self.tlsIdentity = loaded.identity
                        self.certFingerprint = loaded.fingerprint
                    case .failure(let error):
                        self.alertMessage = "Couldn't set up encrypted connections: \(error.localizedDescription)\n\nThe relay runs as ws:// instead."
                        self.useTLS = false
                    }
                    self.apply()
                }
                return
            }
            let identity = useTLS ? tlsIdentity : nil
            if !relayStatus.isRunning || relayStatus.port != port || relayStatus.tls != (identity != nil) {
                do {
                    try NostrRelay.shared.start(port: port, identity: identity)
                } catch {
                    alertMessage = "Couldn't start the relay on port \(port): \(error.localizedDescription)"
                    relayEnabled = false
                }
            }
        } else if relayStatus.isRunning {
            NostrRelay.shared.stop()
        }
        // Public relays only matter once something is paired: don't connect out to them before.
        let urls = relayEnabled || !NostrBridge.shared.allPairings.isEmpty ? bridgeRelays : []
        if urls.isEmpty {
            NostrBridge.shared.stop()
        } else {
            NostrBridge.shared.start(relays: urls, pin: relayPin)
        }
        refresh()
    }

    /// Turns wss:// on or off. Devices paired before have the old addresses: pair them again.
    func setUseTLS(_ on: Bool) {
        guard on != useTLS else { return }
        useTLS = on
        apply()
        if !pairings.isEmpty {
            alertMessage = "Pair your devices again: their pairing links have this relay's \(on ? "ws://" : "wss://") addresses."
        }
    }

    /// "wss" or "ws" for this Mac's relay.
    var relayScheme: String { useTLS ? "wss" : "ws" }

    /// The pinned certificate, when this Mac's relay serves wss://.
    var relayPin: String? { relayEnabled && useTLS ? certFingerprint : nil }

    /// Where the bridge listens: this Mac's relay (over loopback) and the public relays.
    var bridgeRelays: [String] {
        (relayEnabled ? ["\(relayScheme)://127.0.0.1:\(port)"] : []) + extraRelays
    }

    /// Where a paired device connects. With Tailscale Funnel serving this relay: its public
    /// address only (reachable from anywhere, so local and VPN addresses would only add
    /// connections that fail away from home), then public relays. Without it: this Mac's relay on
    /// the local network and VPN, then public relays. The device uses whichever answers first.
    var pairingRelays: [String] {
        guard relayEnabled else { return extraRelays }
        if let funnelURL = funnelURL { return [funnelURL] + extraRelays }
        return lanAddresses.map { "\(relayScheme)://\($0):\(port)" } + vpnAddresses.map { "\(relayScheme)://\($0):\(port)" }
            + extraRelays
    }

    /// wss://<mac>.<tailnet>.ts.net while Tailscale Funnel serves this relay.
    var funnelURL: String? {
        relayEnabled ? TailscaleFunnel.shared.relayURL(port: port, tls: useTLS) : nil
    }

    func addRelay(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: url), ["ws", "wss"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else {
            alertMessage = "Enter a relay address starting with wss:// (or ws://)."
            return false
        }
        if !extraRelays.contains(url) { extraRelays.append(url) }
        apply()
        return true
    }

    func removeRelay(_ url: String) {
        extraRelays.removeAll { $0 == url }
        apply()
    }

    func pair(label: String, chain: String) -> String? {
        let relays = pairingRelays
        guard !relays.isEmpty else {
            alertMessage = "Turn on the relay or add a public relay first: Fully Noded needs somewhere to connect."
            return nil
        }
        let link = NostrBridge.shared.pair(label: label, chain: chain, relays: relays, pin: relayPin)
        if link == nil { alertMessage = "Couldn't create a pairing." }
        apply()
        return link
    }

    /// A Plasma pairing for Core Lightning (made from the Core Lightning page).
    func pairPlasma(label: String, chain: String, rune: String, readOnly: Bool, relays: [String]) -> String? {
        guard !relays.isEmpty else { return nil }
        let link = NostrBridge.shared.pairLightning(label: label, chain: chain, rune: rune, readOnly: readOnly,
                                                    relays: relays, pin: relayPin)
        apply()
        return link
    }

    func unpair(_ pairing: NostrBridge.Pairing) {
        NostrBridge.shared.unpair(pairing.pubkey)
    }

    /// For the sidebar: is anything connected?
    var isConnected: Bool {
        relayStates.values.contains { $0 == .connected }
    }

    static let networks = ["main", "test", "testnet4", "signet", "regtest"]

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

struct NostrConnectView: View {
    @ObservedObject private var model = NostrConnectModel.shared
    @State private var newRelay = ""
    @ObservedObject private var funnel = TailscaleFunnel.shared
    @State private var portText = ""
    @State private var pairLabel = ""
    @State private var pairChain = Defaults.shared.chain
    @State private var pairingLink: String?
    @State private var linkCopied = false
    @State private var confirmUnpair: NostrBridge.Pairing?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                relayCard
                outsideCard
                publicRelaysCard
                pairCard
                devicesCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 560)
        .onAppear {
            portText = String(model.port)
            model.refresh()
        }
        .onReceive(timer) { _ in model.refresh() }
        .sheet(isPresented: Binding(get: { pairingLink != nil }, set: { if !$0 { pairingLink = nil } })) {
            pairingSheet
        }
        .alert(model.alertMessage ?? "", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .alert("Remove \(confirmUnpair?.label ?? "this device")?", isPresented: Binding(
            get: { confirmUnpair != nil },
            set: { if !$0 { confirmUnpair = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let pairing = confirmUnpair { model.unpair(pairing) }
                confirmUnpair = nil
            }
            Button("Cancel", role: .cancel) { confirmUnpair = nil }
        } message: {
            Text("It can no longer reach this node over nostr. Pair it again to reconnect.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("Nostr Connect")
                    .font(Cypher.mono(20, weight: .bold))
            }
            Text("A fast alternative to Tor for Fully Noded. Fully Noded and this server talk through a nostr relay over WebSockets, end-to-end encrypted (NIP-44): a relay only passes on ciphertext. Run the relay on this Mac for the local network, and add a public relay to reach your node from anywhere.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var relayCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { model.relayEnabled }, set: { model.relayEnabled = $0; model.apply() })) {
                    Text("Run a relay on this Mac")
                }
                .toggleStyle(.switch)
                Toggle(isOn: Binding(get: { model.useTLS }, set: { model.setUseTLS($0) })) {
                    Text("Encrypt connections (wss://)")
                }
                .toggleStyle(.switch)
                .disabled(!RelayTLS.isSupported)
                Text(RelayTLS.isSupported
                     ? "TLS with a certificate this Mac made for itself. Its fingerprint goes in the pairing link, so Fully Noded accepts exactly this certificate. Messages are end-to-end encrypted either way; wss:// also hides who's talking to whom from others on the network.\(model.certFingerprint.map { "\nCertificate SHA-256: \($0.prefix(16))…" } ?? "")"
                     : "Encrypted connections (wss://) need macOS 15 or later.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack {
                    Text("Port")
                    TextField("7777", text: $portText)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyPort)
                    Button("Apply", action: applyPort)
                        .disabled(UInt16(portText) == model.port)
                    Spacer()
                }
                statusLine
                Text("Only Fully Noded devices you pair can publish to it, and it stores nothing. macOS may ask once whether Fully Noded Server may accept incoming connections: allow it, or devices on your network can't connect.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Text("Relay")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let s = model.relayStatus
        if let error = s.lastError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Cypher.amber)
        } else if s.isRunning {
            VStack(alignment: .leading, spacing: 4) {
                Label("Running · \(s.connections) connection\(s.connections == 1 ? "" : "s") · \(s.eventsRelayed) messages relayed",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Cypher.accent)
                ForEach(model.lanAddresses, id: \.self) { ip in
                    Text(verbatim: "\(s.tls ? "wss" : "ws")://\(ip):\(s.port)")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.text)
                        .textSelection(.enabled)
                }
            }
        } else {
            Label("Off", systemImage: "circle").foregroundStyle(Cypher.dim)
        }
    }

    private func applyPort() {
        guard let p = UInt16(portText), p >= 1024 else {
            model.alertMessage = "Use a port from 1024 to 65535."
            return
        }
        model.port = p
        model.apply()
    }

    private var outsideCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.vpnAddresses, id: \.self) { ip in
                    HStack {
                        Image(systemName: "network.badge.shield.half.filled").foregroundStyle(Cypher.accent)
                        Text(verbatim: "\(model.relayScheme)://\(ip):\(model.port)").font(Cypher.mono(12)).textSelection(.enabled)
                        Text("VPN, added automatically").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    }
                }
                funnelSection
            }
        } label: {
            Text("Reach this relay from anywhere · Tailscale Funnel")
        }
        .onAppear { funnel.refresh() }
    }

    @ViewBuilder
    private var funnelSection: some View {
        Text("Tailscale Funnel gives this Mac's relay a public wss:// address with a trusted certificate. Fully Noded and Plasma then reach it from any network, with nothing to install on the phone, no port forward and no ngrok. Only this Mac needs Tailscale (and Fully Noded Server running). Everything stays end-to-end encrypted, and only paired devices can publish.")
            .font(Cypher.mono(11))
            .foregroundStyle(Cypher.dim)
            .fixedSize(horizontal: false, vertical: true)

        if !funnel.status.installed {
            HStack(spacing: 8) {
                Link("Get Tailscale for Mac", destination: TailscaleFunnel.downloadURL)
                Button("Check again") { funnel.refresh() }
            }
        } else if !funnel.status.running || funnel.status.host == nil {
            Label("Tailscale isn't connected. Open it, sign in and turn it on.", systemImage: "exclamationmark.triangle.fill")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.amber)
            HStack(spacing: 8) {
                Button("Open Tailscale") { funnel.openTailscale() }
                Button("Check again") { funnel.refresh() }
            }
        } else if !model.relayEnabled {
            Text("Turn on \"Run a relay on this Mac\" above first.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
        } else if let url = model.funnelURL {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Cypher.accent)
                Text(url).font(Cypher.mono(12, weight: .semibold)).textSelection(.enabled)
                Spacer()
                Button("Turn off") { funnel.turnOff { model.refresh() } }
                    .disabled(funnel.busy)
            }
            funnelReachability
            Text("Checked from the internet every few minutes; if it stops answering, Funnel is turned off and on. New pairings use only this address (plus any public relays): it works on every network. Pair devices again to switch them to it.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
        } else {
            if funnel.status.funnelOn, let target = funnel.status.target {
                Label("Funnel is on, but serves \(target) instead of this relay\(model.useTLS ? " (wss://)" : "").", systemImage: "exclamationmark.triangle.fill")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    funnel.turnOn(port: model.port, tls: model.useTLS) { model.refresh() }
                } label: {
                    Image(systemName: "globe")
                    Text(funnel.status.funnelOn ? "Point Funnel at this relay" : "Turn on Funnel")
                }
                .buttonStyle(.cypherProminent)
                .disabled(funnel.busy)
                if funnel.busy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { funnel.cancel() }
                }
                Text("https://\(funnel.status.host ?? "")")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
            }
            if let approval = funnel.approvalURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tailscale needs HTTPS certificates and Funnel allowed for this Mac (once). Approve it in the browser; Funnel turns on by itself afterwards.")
                        .font(Cypher.mono(11))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Approve in Tailscale") { NSWorkspace.shared.open(approval) }
                        .buttonStyle(.cypherProminent)
                }
            }
        }

        if let error = funnel.error {
            Text(error)
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.danger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var funnelReachability: some View {
        HStack(spacing: 8) {
            switch funnel.reachability {
            case .reachable(let date):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Cypher.accent)
                Text("Reachable from anywhere · checked \(date.formatted(date: .omitted, time: .shortened))")
                    .font(Cypher.mono(11))
            case .unknown, .checking:
                Image(systemName: "globe").foregroundStyle(Cypher.dim)
                Text("Verifying public access…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            case .repairing:
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Cypher.dim)
                Text("Reconnecting Funnel…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            case .unreachable(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Cypher.amber)
                Text("Funnel isn't answering from outside: paired devices use the public relays meanwhile. \(reason)")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.amber)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if case .unreachable = funnel.reachability {
                Button("Reconnect") { funnel.repair() }.disabled(funnel.busy)
            }
        }
    }

    private var publicRelaysCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.extraRelays, id: \.self) { url in
                    HStack {
                        relayStateIcon(url)
                        Text(url).font(Cypher.mono(12)).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { model.removeRelay(url) }
                    }
                }
                HStack {
                    TextField("wss://relay.example.com", text: $newRelay)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addRelay)
                    Button("Add", action: addRelay)
                        .disabled(newRelay.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.relayEnabled {
                    HStack {
                        relayStateIcon("\(model.relayScheme)://127.0.0.1:\(model.port)")
                        Text("This Mac's relay").font(Cypher.mono(12))
                    }
                }
                Text("Public relays let paired devices reach your node from anywhere, even when this Mac's relay can't be reached from outside. A few are included by default. Pair (or re-pair) devices after changing them so their link includes them. A relay operator sees that two keys exchange messages and when, never the contents.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Text("Relays the bridge listens on")
        }
    }

    private func addRelay() {
        if model.addRelay(newRelay) { newRelay = "" }
    }

    @ViewBuilder
    private func relayStateIcon(_ url: String) -> some View {
        switch model.relayStates[url] {
        case .connected?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Cypher.accent).help("Connected")
        case .failed(let reason)?:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Cypher.amber).help(reason)
        case .connecting?:
            ProgressView().controlSize(.small)
        case nil:
            Image(systemName: "circle").foregroundStyle(Cypher.dim)
        }
    }

    private var pairCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Device name, e.g. My iPhone", text: $pairLabel)
                        .textFieldStyle(.roundedBorder)
                    Picker("Network", selection: $pairChain) {
                        ForEach(NostrConnectModel.networks, id: \.self) { Text(NostrConnectModel.networkName($0)).tag($0) }
                    }
                    .frame(width: 180)
                }
                if model.pairingRelays.isEmpty {
                    Text("Turn on the relay or add a public relay first.")
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
                } else {
                    Text("Connects through: " + model.pairingRelays.joined(separator: ", "))
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Pair Fully Noded") {
                        let label = pairLabel.trimmingCharacters(in: .whitespaces)
                        if let link = model.pair(label: label.isEmpty ? "Fully Noded" : label, chain: pairChain) {
                            linkCopied = false
                            pairingLink = link
                            pairLabel = ""
                        }
                    }
                    .buttonStyle(.cypherProminent)
                    .disabled(model.pairingRelays.isEmpty)
                }
            }
        } label: {
            Text("Pair a device")
        }
    }

    private var devicesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.pairings.isEmpty {
                    Text("No devices paired yet.").font(Cypher.mono(12)).foregroundStyle(Cypher.dim)
                }
                ForEach(model.pairings) { pairing in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pairing.label).font(Cypher.mono(12, weight: .semibold))
                            Text((pairing.isLightning ? "Plasma · Core Lightning\(pairing.readOnly == true ? " (read-only)" : "") · " : "") +
                                 "\(NostrConnectModel.networkName(pairing.chain)) · " +
                                 (pairing.lastSeen.map { "last seen \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "not used yet"))
                                .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        }
                        Spacer()
                        Button("Remove") { confirmUnpair = pairing }
                    }
                }
            }
        } label: {
            Text("Paired devices")
        }
    }

    private var pairingSheet: some View {
        VStack(spacing: 14) {
            Text("Pair Fully Noded")
                .font(Cypher.mono(16, weight: .bold))
            Text("In Fully Noded, scan this QR when adding a node (or open the link on the device). It's shown once: anyone with it can use your node, so don't share it.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let link = pairingLink {
                Image(nsImage: link.qrQode)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 300, height: 300)
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link, forType: .string)
                        linkCopied = true
                    } label: {
                        Label(linkCopied ? "Copied" : "Copy link", systemImage: linkCopied ? "checkmark" : "doc.on.doc")
                    }
                    Button("Done") { pairingLink = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .cypherTheme()
    }
}

/// The sidebar icon for the Nostr Connect row.
struct NostrConnectSidebarIcon: View {
    @ObservedObject private var model = NostrConnectModel.shared
    @ObservedObject private var funnel = TailscaleFunnel.shared

    /// Funnel serves the relay but doesn't answer from the internet.
    private var funnelDown: Bool {
        guard model.funnelURL != nil else { return false }
        if case .unreachable = funnel.reachability { return true }
        return false
    }

    var body: some View {
        if model.isConnected && !funnelDown {
            Image(systemName: "checkmark").foregroundStyle(Cypher.accent)
        } else if model.relayEnabled || !model.pairings.isEmpty {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Cypher.amber)
        } else {
            Image(systemName: "xmark").foregroundStyle(Cypher.dim)
        }
    }
}
