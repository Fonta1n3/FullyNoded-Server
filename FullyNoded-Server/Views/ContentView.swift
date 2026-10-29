//
//  ContentView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI
import Network

public struct Service: Identifiable {
    let name: String
    public let id: UUID
    
    init(name: String, id: UUID) {
        self.name = name
        self.id = id
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var useKnots = UserDefaults.standard.value(forKey: "useKnots") as? Bool ?? false
    @State private var bitcoinKnotsInstalled = false
    @State private var promptToShowPythonGuide = false
    @State private var isInitialLoad = true
    @State private var torProgress = 0.0
    @State private var showError = false
    @State private var message = ""
    @State private var services: [Service] = []
    @State private var bitcoinCoreInstalled = false
    @State private var joinMarketInstalled = false
    @State private var promptToInstallXcode = false
    @State private var promptToInstallBitcoin = false
    @State private var startCheckingForBitcoinInstall = false
    @State private var bitcoinInstallSuccess = false
    @State private var timeRemaining = 90
    @State private var promptToInstallBrew = false
    @State private var torRunning = false
    @State private var showingBitcoinReleases = false
    @State private var env: [String: String] = [:]
    @State private var jmTaggedReleases: TaggedReleases = []
    @State private var taggedReleases: TaggedReleases? = nil
    @State private var bitcoinEnvValues: BitcoinEnvValues = .init(dictionary: [
        "binaryName": "bitcoin-27.2-arm64-apple-darwin.tar.gz",
        "version": "27.2",
        "prefix": "bitcoin-27.2",
        "dataDir": Defaults.shared.bitcoinDataDir,
        "chain": Defaults.shared.chain
    ])
    
    @State private var knotsEnvValues: BitcoinKnotsEnvValues = .init(dictionary: [:])
    
    private let timerForBitcoinKnotsInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForJMInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForTor = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let bitcoinCore = Service(name: "Bitcoin Core", id: UUID())
    private let bitcoinKnots = Service(name: "Bitcoin Knots", id: UUID())
    private let coreLightning = Service(name: "Core Lightning", id: UUID())
    private let joinMarket = Service(name: "Join Market", id: UUID())
    private let silentPayments = Service(name: "Silent Payments", id: UUID())
    private let nostrConnect = Service(name: "Nostr Connect", id: UUID())
    private let tor = Service(name: "Tor", id: UUID())
    private let help = Service(name: "Help", id: UUID())
    private let settings = Service(name: "Settings", id: UUID())
    

    /// Each service's page has its own colour (CypherPalette).
    static func palette(for service: String) -> CypherPalette {
        switch service {
        case "Bitcoin Core": return .bitcoinCore
        case "Bitcoin Knots": return .bitcoinKnots
        case "Core Lightning": return .lightning
        case "Join Market": return .joinMarket
        case "Silent Payments": return .silentPayments
        case "Nostr Connect": return .nostr
        case "Tor": return .tor
        case "Settings": return .settings
        case "Help": return .help
        default: return .standard
        }
    }

    /// The sidebar's sections: the node, what runs on it, then the app itself.
    static func groups(_ services: [Service]) -> [(title: String, services: [Service])] {
        let nodes = ["Bitcoin Core", "Bitcoin Knots", "Core Lightning"]
        let app = ["Settings", "Help"]
        return [
            ("NODE", services.filter { nodes.contains($0.name) }),
            ("SERVICES", services.filter { !nodes.contains($0.name) && !app.contains($0.name) }),
            ("APP", services.filter { app.contains($0.name) })
        ].filter { !$0.1.isEmpty }.map { (title: $0.0, services: $0.1) }
    }

    /// The window subtitle under each page's title.
    static func tagline(for service: String) -> String {
        switch service {
        case "Bitcoin Core", "Bitcoin Knots": return "Your bitcoin node"
        case "Core Lightning": return "Your lightning node, for Plasma"
        case "Join Market": return "Coinjoins"
        case "Silent Payments": return "Scan for private payments"
        case "Nostr Connect": return "Reach your node from Fully Noded and Plasma"
        case "Tor": return "Onion services"
        case "Settings": return "Configuration"
        case "Help": return "Support & links"
        default: return ""
        }
    }

    static func symbol(for service: String) -> String {
        switch service {
        case "Bitcoin Core", "Bitcoin Knots": return "bitcoinsign.circle"
        case "Core Lightning": return "bolt"
        case "Join Market": return "arrow.triangle.merge"
        case "Silent Payments": return "eye.slash"
        case "Nostr Connect": return "antenna.radiowaves.left.and.right"
        case "Tor": return "network.badge.shield.half.filled"
        case "Settings": return "gearshape"
        case "Help": return "questionmark.circle"
        default: return "circle"
        }
    }

    var body: some View {
            NavigationView {
                List {
                    ForEach(Self.groups(services), id: \.title) { group in
                    Section {
                    ForEach(group.services) { service in
                        NavigationLink {
                        Group {
                            if service.name == "Bitcoin Core" {
                                if bitcoinCoreInstalled {
                                    BitcoinCore()
                                } else {
                                    Home(
                                        showBitcoinCoreInstallButton: true,
                                        showBitcoinKnotsInstallButton: false,
                                        env: env,
                                        showJoinMarketInstallButton: false,
                                        jmTaggedReleases: []
                                    )
                                }
                            } else if service.name == "Bitcoin Knots" {
                                if bitcoinKnotsInstalled {
                                    BitcoinKnots()
                                } else {
                                    Home(
                                        showBitcoinCoreInstallButton: false,
                                        showBitcoinKnotsInstallButton: true,
                                        env: env,
                                        showJoinMarketInstallButton: false,
                                        jmTaggedReleases: []
                                    )
                                }
                            } else if service.name == "Core Lightning" {
                                CoreLightning()
                            } else if service.name == "Join Market" {
                                if joinMarketInstalled {
                                    JoinMarket()
                                } else {
                                    if !bitcoinCoreInstalled {
                                        Text("First install Bitcoin Core.")
                                    }
                                    Home(
                                        showBitcoinCoreInstallButton: false,
                                        showBitcoinKnotsInstallButton: false,
                                        env: env,
                                        showJoinMarketInstallButton: true,
                                        jmTaggedReleases: jmTaggedReleases
                                    )
                                }
                            } else if service.name == "Silent Payments" {
                                SilentPaymentsView()
                            } else if service.name == "Nostr Connect" {
                                NostrConnectView()
                            } else if service.name == "Tor" {
                                TorView()
                            } else if service.name == "Help" {
                                Help()
                            } else if service.name == "Settings" {
                                Settings(bitcoinEnvValues: bitcoinEnvValues, knotsEnvValues: knotsEnvValues)
                            }
                        }
                        .modifier(PageChrome(service: service.name))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: Self.symbol(for: service.name))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Cypher.accent)
                                    .frame(width: 20)
                                Text(service.name)
                                    .font(Cypher.mono(13, weight: .medium))
                                    .foregroundStyle(Cypher.text)
                                Spacer(minLength: 8)
                                if service.name == "Bitcoin Core" {
                                    if bitcoinCoreInstalled {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Cypher.accent)
                                    } else {
                                        Image(systemName: "xmark")
                                            .foregroundStyle(Cypher.dim)
                                        EmptyView()
                                            .onReceive(timerForBitcoinInstall) { _ in
                                                DataManager.retrieve(entityName: .bitcoinEnv) { bitcoinEnv in
                                                    guard let bitcoinEnv = bitcoinEnv else { return }
                                                    let envValues = BitcoinEnvValues(dictionary: bitcoinEnv)
                                                    let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(envValues.prefix)/bin/bitcoind"
                                                    if FileManager.default.fileExists(atPath: tempPath) {
                                                        bitcoinCoreInstalled = true
                                                        self.timerForBitcoinInstall.upstream.connect().cancel()
                                                        getJmRelease()
                                                    }
                                                }
                                                
                                            }
                                    }
                                }
                                
                                if service.name == "Bitcoin Knots" {
                                    if bitcoinKnotsInstalled {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Cypher.accent)
                                    } else {
                                        Image(systemName: "xmark")
                                            .foregroundStyle(Cypher.dim)
                                        EmptyView()
                                            .onReceive(timerForBitcoinKnotsInstall) { _ in
                                                DataManager.retrieve(entityName: .bitcoinKnotsEnv) { bitcoinKnotsEnv in
                                                    guard let bitcoinKnotsEnv = bitcoinKnotsEnv else { return }
                                                    let envValues = BitcoinKnotsEnvValues(dictionary: bitcoinKnotsEnv)
                                                    self.knotsEnvValues = envValues
                                                    let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinKnots/\(envValues.prefix)/bin/bitcoind"
                                                    if FileManager.default.fileExists(atPath: tempPath) {
                                                        bitcoinKnotsInstalled = true
                                                        self.timerForBitcoinKnotsInstall.upstream.connect().cancel()
                                                    }
                                                }
                                            }
                                    }
                                }
                                
                                if service.name == "Core Lightning" {
                                    LightningSidebarIcon()
                                }
                                
                                if service.name == "Join Market" {
                                    if joinMarketInstalled {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Cypher.accent)
                                    } else {
                                        Image(systemName: "xmark")
                                            .foregroundStyle(Cypher.dim)
                                        EmptyView()
                                            .onReceive(timerForJMInstall) { _ in
                                                if let tagName = UserDefaults.standard.string(forKey: "tagName") {
                                                    let jmConfigPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
                                                    
                                                    if FileManager.default.fileExists(atPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName)/scripts/jmwalletd.py") && FileManager.default.fileExists(atPath: jmConfigPath) {
                                                        joinMarketInstalled = true
                                                        self.timerForJMInstall.upstream.connect().cancel()
                                                    }
                                                }
                                            }
                                    }
                                }
                                
                                if service.name == "Silent Payments" {
                                    SPSidebarStatusIcon()
                                }

                                if service.name == "Nostr Connect" {
                                    NostrConnectSidebarIcon()
                                }
                                
                                if service.name == "Tor" {
                                    if torProgress < 100.0 {
                                        ProgressView()
#if os(macOS)
                                            .scaleEffect(0.5)
#endif
                                    } else {
                                        if torRunning {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Cypher.accent)
                                        } else {
                                            Image(systemName: "xmark")
                                                .foregroundStyle(Cypher.dim)
                                        }
                                    }
                                    
                                    EmptyView()
                                        .onReceive(timerForTor) { _ in
                                            self.torRunning = TorClient.sharedInstance.state == .connected
                                        }
                                }
                                
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.vertical, 3)
                        }
                    }
                    } header: {
                        Text(group.title)
                            .font(Cypher.mono(10, weight: .bold))
                            .foregroundStyle(Cypher.dim)
                            .padding(.top, 6)
                    }
                    }
                }
                .padding(.vertical)
                .listStyle(.sidebar)
                .frame(minWidth: 250)
                .background(Cypher.panel)
                .safeAreaInset(edge: .top) {
                    HStack(spacing: 10) {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("FULLY NODED")
                                .font(Cypher.mono(12, weight: .bold))
                                .foregroundStyle(Cypher.accent)
                            Text("SERVER")
                                .font(Cypher.mono(10, weight: .semibold))
                                .foregroundStyle(Cypher.dim)
                                .kerning(3)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Cypher.line).frame(height: 1).padding(.horizontal, 16)
                    }
                }
                VStack(spacing: 8) {
                    CypherCaption("Fully Noded Server")
                    Text("Select a service.")
                        .foregroundStyle(Cypher.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Cypher.bg)
                .navigationTitle("Fully Noded Server")
            }
            .modifier(MainToolbar(useKnots: useKnots))
        
        .onAppear(perform: {
            guard isInitialLoad else { return }
            bootTor()
            // The sidebar doesn't wait for the developer tool checks (only JoinMarket needs them).
            getSavedValues()
            presentSetupAssistantIfNeeded()
        })
        // Its own window (a sheet was taller than the main window and got clipped).
        .onReceive(NotificationCenter.default.publisher(for: .showSetupAssistant)) { _ in
            openWindow(id: "SetupAssistant")
        }
        .onReceive(NotificationCenter.default.publisher(for: .setupAssistantFinished)) { _ in
            // New implementation / network / install: reload what the sidebar shows.
            useKnots = UserDefaults.standard.value(forKey: "useKnots") as? Bool ?? false
            getSavedValues()
        }
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Python 3.10-3.12 is a Join Market dependency. Would you like to see a guide on how to easily install it?", isPresented: $promptToShowPythonGuide) {
                    Link("Open Python install guide", destination: URL(string: "https://www.codingforentrepreneurs.com/guides/install-python-on-macos")!)
        }
        .alert("Install Homebrew? Join Market's installation relies on it.", isPresented: $promptToInstallBrew) {
            Button("Install Homebrew") {
                ScriptUtil.runScript(script: .installHomebrew, env: nil, args: nil) { (_, _, _) in }
            }
            Button("Not now", role: .cancel) {}
        }
        .alert("Install Xcode Command Line Tools? This is required for Fully Noded - Server to function.", isPresented: $promptToInstallXcode, actions: {
            Button("OK", role: .cancel) {
                ScriptUtil.runScript(script: .installXcode, env: nil, args: nil) { (_, _, _) in }
            }
        })
        .alert("Bitcoin Install complete.", isPresented: $bitcoinInstallSuccess) {
            Button("OK", role: .cancel) {
                checkForBitcoin()
            }
        }
        .alert("A terminal should have launched to install Bitcoin Core, close the terminal window when it says its finished.", isPresented: $startCheckingForBitcoinInstall) {
            Button("OK", role: .cancel) {}
        }        
    }
    
    private func checkForXcode() {
        ScriptUtil.runScript(script: .checkXcodeSelect, env: nil, args: nil) { (output, data, errorMess) in
            guard let output = output else {
                showMessage(message: errorMess ?? "Unknown error checking for xcode select.")
                return
            }
            if output.contains("XCode select installed") {
                promptToInstallXcode = false
                checkForBrew()
            } else if output.contains("XCode select not installed") {
                promptToInstallXcode = true
            }
        }
    }
    
    private func bootTor() {
        if TorClient.sharedInstance.state == .connected {
            torProgress = 100.0
        } else {
            TorClient.sharedInstance.start(delegate: nil)
        }
        TorClient.sharedInstance.showProgress = { progress in
            torProgress = Double(progress)
        }
        isInitialLoad = false
    }
    
    private func checkForBrew() {
        ScriptUtil.runScript(script: .checkForBrew, env: nil, args: nil) { (output, data, errorMess) in
            guard let output = output, output != "" else {
                promptToInstallBrew = true
                return
            }
        }
    }
    
    /// First run (setup never finished or skipped, and no node installed): open the Setup
    /// Assistant, which covers the developer tools too. Otherwise the usual tool prompts.
    private func presentSetupAssistantIfNeeded() {
        guard !SetupAssistant.isComplete else {
            checkForXcode()
            return
        }
        NodeImplementation.core.installedEnv { coreEnv in
            NodeImplementation.knots.installedEnv { knotsEnv in
                DispatchQueue.main.async {
                    if coreEnv == nil && knotsEnv == nil {
                        openWindow(id: "SetupAssistant")
                    } else {
                        // Set up before the assistant existed: don't open it by itself.
                        SetupAssistant.isComplete = true
                        checkForXcode()
                    }
                }
            }
        }
    }
    
    private func rebuildServices() {
        if useKnots {
            services = [bitcoinKnots, coreLightning, joinMarket, silentPayments, nostrConnect, tor, settings, help]
        } else {
            services = [bitcoinCore, coreLightning, joinMarket, silentPayments, nostrConnect, tor, settings, help]
        }
    }
    
    private func getSavedValues() {
        DataManager.retrieve(entityName: .bitcoinEnv) { bitcoinEnv in
            guard let bitcoinEnv = bitcoinEnv else {
                let dict = [
                    "binaryName": "bitcoin-27.2-arm64-apple-darwin.tar.gz",
                    "version": "27.2",
                    "prefix": "bitcoin-27.2",
                    "dataDir": Defaults.shared.bitcoinDataDir,
                    "chain": Defaults.shared.chain
                ]
                
                DataManager.saveEntity(entityName: .bitcoinEnv, dict: dict) { saved in
                    guard saved else {
                        showMessage(message: "Unable to save default bitcoin env values.")
                        return
                    }
                    
                    self.env = [
                        "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                        "VERSION": self.bitcoinEnvValues.version,
                        "PREFIX": self.bitcoinEnvValues.prefix,
                        "DATADIR": Defaults.shared.bitcoinDataDir,
                        "CHAIN": self.bitcoinEnvValues.chain
                    ]
                    
                    rebuildServices()
                    checkForBitcoin()
                }
                
                return
            }
            
            
            self.bitcoinEnvValues = .init(dictionary: bitcoinEnv)
            
            self.env = [
                "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                "VERSION": self.bitcoinEnvValues.version,
                "PREFIX": self.bitcoinEnvValues.prefix,
                "DATADIR": Defaults.shared.bitcoinDataDir,
                "CHAIN": self.bitcoinEnvValues.chain
            ]
            
            rebuildServices()
            checkForBitcoin()
        }
    }

    
    
    private func checkForBitcoin() {
        ScriptUtil.runScript(script: .checkForBitcoin, env: env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else if let output = output {
                    parseBitcoindVersionResponse(result: output)
                }
                return
            }
            guard let output = output else { return }
            parseBitcoindVersionResponse(result: output)
        }
    }
    
    func parseBitcoindVersionResponse(result: String) {
        if result.contains("Bitcoin Core Daemon version") || result.contains("Bitcoin Core version") {
            bitcoinCoreInstalled = true
            let tempPath = "/Users/\(NSUserName())/.fullynoded/installBitcoin.sh"
            if FileManager.default.fileExists(atPath: tempPath) {
                try? FileManager.default.removeItem(atPath: tempPath)
            }
            
            if let tagName = UserDefaults.standard.object(forKey: "tagName") as? String {
                let jmWalletDPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName)/scripts/jmwalletd.py"
                guard !FileManager.default.fileExists(atPath: jmWalletDPath)  else {
                    joinMarketInstalled = true
                    return
                }
                
                guard FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.10") || FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.11") ||
                      FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.12") else {
                    promptToShowPythonGuide = true
                    return
                }
                getJmRelease()
            }            
            
        } else {
            bitcoinCoreInstalled = false
            promptToInstallBitcoin = true
        }
    }
    
    private func getJmRelease() {
        LatestJoinMarketRelease.get { (releases, error) in
            if let releases = releases {
                jmTaggedReleases = releases
            }
        }
    }
        
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func parseXcodeSelectResult(result: String) {
        if result.contains("XCode select not installed") {
            promptToInstallXcode = true
        } else {
            promptToInstallXcode = false
            
            LatestBtcCoreRelease.get { (taggedReleases, error) in
                guard let taggedReleases = taggedReleases else {
                    showMessage(message: error ?? "Unknown issue downloading bitcoin core release.")
                    return
                }
                self.taggedReleases = taggedReleases
                showingBitcoinReleases = true
            }
        }
    }
}


private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

/// A sidebar page: its palette, and its name and tagline in the window's title bar.
private struct PageChrome: ViewModifier {
    let service: String

    func body(content: Content) -> some View {
        content
            .cypherPage(ContentView.palette(for: service))
            .navigationTitle(service)
            .navigationSubtitle(ContentView.tagline(for: service))
    }
}

/// The main window's toolbar: status chips and the Setup Assistant.
private struct MainToolbar: ViewModifier {
    let useKnots: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                // The square status chips sit on the bar itself: macOS 26 would otherwise put
                // them on a rounded glass capsule that clips their corners.
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .primaryAction) {
                        ToolbarStatus(useKnots: useKnots)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        ToolbarStatus(useKnots: useKnots)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: .showSetupAssistant, object: nil)
                    } label: {
                        Label("Setup Assistant", systemImage: "wand.and.stars")
                    }
                    .help("Setup Assistant")
                }
            }
            .toolbarBackground(Cypher.panel, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
    }
}

/// Window toolbar: network, the node, Tor and Nostr Connect at a glance (each a dot and a word).
private struct ToolbarStatus: View {
    let useKnots: Bool
    @ObservedObject private var core = NodeMonitor.core
    @ObservedObject private var knots = NodeMonitor.knots
    @ObservedObject private var nostr = NostrConnectModel.shared

    var body: some View {
        // Tor isn't observable: re-read it every few seconds.
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            HStack(spacing: 6) {
                chip(NodeMonitor.networkName(Defaults.shared.chain).uppercased(), state: nil,
                     help: "Bitcoin network")
                chip(useKnots ? "KNOTS" : "CORE", state: nodeState, help: nodeHelp)
                chip("TOR", state: TorClient.sharedInstance.state == .connected ? .ok
                        : (TorClient.sharedInstance.state == .started || TorClient.sharedInstance.state == .refreshing ? .pending : .off),
                     help: "Tor")
                if nostr.relayEnabled || !nostr.pairings.isEmpty {
                    chip("NOSTR", state: nostr.isConnected ? .ok : .pending, help: "Nostr Connect")
                }
            }
        }
    }

    private enum ChipState { case ok, pending, off }

    private var monitor: NodeMonitor { useKnots ? knots : core }

    private var nodeState: ChipState? {
        switch monitor.phase {
        case .running: return .ok
        case .starting, .stopping: return .pending
        case .stopped, .failed: return .off
        default: return nil
        }
    }

    private var nodeHelp: String {
        switch monitor.phase {
        case .running: return "Node running"
        case .starting, .stopping: return "Node changing state"
        case .stopped: return "Node stopped"
        case .failed(let reason): return "Node failed: \(reason)"
        default: return "Node status: open its page to check"
        }
    }

    private func chip(_ title: String, state: ChipState?, help: String) -> some View {
        HStack(spacing: 5) {
            if let state {
                Circle()
                    .fill(state == .ok ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(state == .pending ? Cypher.amber : Cypher.danger))
                    .frame(width: 6, height: 6)
            }
            Text(verbatim: title)
                .font(Cypher.mono(10, weight: .bold))
                .foregroundStyle(state == nil ? AnyShapeStyle(Cypher.dim) : AnyShapeStyle(Cypher.text))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
        .help(help)
    }
}

#Preview {
    ContentView()
}
