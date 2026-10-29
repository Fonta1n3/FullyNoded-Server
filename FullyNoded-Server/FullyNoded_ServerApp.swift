//
//  FullyNoded_ServerApp.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI
import AppKit

@main
struct FullyNoded_ServerApp: App {
    
    @Environment(\.openWindow) var openWindow
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var isRunning = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var blockchainInfo: BlockchainInfo?
    
    /// Another Fully Noded Server already running (often an older build left open while a new
    /// one launches from Xcode) keeps the relay's port, so this copy's relay can't start. Asks to
    /// quit the other copy, waits for it to exit, then continues.
    static func resolveOtherInstances(then continueLaunch: @escaping () -> Void) {
        let me = NSRunningApplication.current
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != me.processIdentifier &&
            ($0.bundleIdentifier == me.bundleIdentifier || $0.executableURL?.lastPathComponent == me.executableURL?.lastPathComponent)
        }
        guard !others.isEmpty else { continueLaunch(); return }
        let alert = NSAlert()
        alert.messageText = "Fully Noded Server is already running"
        alert.informativeText = "Another copy (pid \(others.map { String($0.processIdentifier) }.joined(separator: ", "))) is open. Only one copy can run the Nostr Connect relay and manage your nodes. Quit the other copy?"
        alert.addButton(withTitle: "Quit the other copy")
        alert.addButton(withTitle: "Keep both")
        guard alert.runModal() == .alertFirstButtonReturn else { continueLaunch(); return }
        others.forEach { $0.terminate() }
        // Give it up to 10 s to quit (it stops its relay and saves state), then force it.
        func wait(_ attempt: Int) {
            if others.allSatisfy({ $0.isTerminated }) { continueLaunch(); return }
            if attempt == 20 { others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() } }
            if attempt > 30 { continueLaunch(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wait(attempt + 1) }
        }
        wait(0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { SPImportedCard() }
                .cypherTheme()
                .onAppear {
                    if UserDefaults.standard.value(forKey: "encKeyFullyNodedServer") as? String == nil {
                        UserDefaults.standard.setValue(Crypto.privKeyData().base64EncodedString(), forKey: "encKeyFullyNodedServer")
                    }
                    initialLoad()
                    // Callbacks first (they raise the "silent payment received" alert),
                    // then keep scanning if keys were imported before.
                    _ = SilentPaymentsModel.shared
                    SPConfigStore.resumeIfConfigured()
                    // Nostr Connect: relay and bridge back on if they were. Another running copy
                    // holds the relay's port, so offer to quit it first.
                    Self.resolveOtherInstances {
                        NostrConnectModel.shared.startIfConfigured()
                    }
                }
                // fnsp:// links (Fully Noded's silent payment export): fill the form and show it
                // so the user can check it and start scanning.
                .onOpenURL { url in
                    guard SilentPaymentsModel.shared.applyImportLink(url.absoluteString) else { return }
                    openWindow(id: "SilentPayments")
                    NSApp.activate(ignoringOtherApps: true)
                }
                // Reuse the open main window for links instead of opening another one.
                .handlesExternalEvents(preferring: ["fnsp"], allowing: ["*"])
        }
        // Links are handled by this window (created on a cold start, so the usual launch work
        // runs); every other window ignores them.
        .handlesExternalEvents(matching: ["fnsp"])
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Setup Assistant…") {
                    NotificationCenter.default.post(name: .showSetupAssistant, object: nil)
                }
            }
        }
        Window("Setup Assistant", id: "SetupAssistant") {
            SetupAssistantView {
                NotificationCenter.default.post(name: .setupAssistantFinished, object: nil)
            }
            .cypherTheme()
            .toolbarBackground(Cypher.panel, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
        Window("Utilities", id: "Utilities-JM") {
            JMUtilsView()
                .cypherPage(.joinMarket)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("QuickConnect", id: "QuickConnect-JM") {
            JMQuickConnectView()
                .cypherPage(.joinMarket)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Utilities", id: "Utilities") {
            BtcUtilsView()
                .cypherPage(.bitcoinCore)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Utilities", id: "Utilities-Knots") {
            KnotsUtilsView()
                .cypherPage(.bitcoinKnots)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("QuickConnect", id: "QuickConnect") {
            QuickConnectView()
                .cypherPage(.bitcoinCore)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        // Opened from the Setup Assistant (the sidebar page is the same view).
        Window("Nostr Connect", id: "NostrConnect") {
            NostrConnectView()
                .cypherPage(.nostr)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Silent Payments", id: "SilentPayments") {
            SilentPaymentsView()
                .cypherPage(.silentPayments)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Blockchain Info", id: "BlockchainInfo") {
            if let blockchainInfo = blockchainInfo {
                BlockchainInfoView(blockchainInfo: blockchainInfo)
                    .cypherPage(.bitcoinCore)
                    .cypherTheme()
            }
        }
        .handlesExternalEvents(matching: [])
        Window("Silent Payment History", id: "SPHistory") {
            SPHistoryView()
                .cypherPage(.silentPayments)
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        MenuBarExtra() {
            Button("Start core") {
                ScriptUtil.runScript(script: .startBitcoin, env: env, args: nil) { (_, _, _) in }
            }
            Button("Stop core") {
                BitcoinRPC.shared.command(method: "stop", params: [:]) { (result, error) in
                    guard let _ = result as? String else {
                        return
                    }
                    isRunning = false
                }
            }
            Button("Silent payment history") {
                openWindow(id: "SPHistory")
            }
            Button("Info") {
                BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
                    guard let result = result as? [String: Any] else {
                        return
                    }
                    blockchainInfo = BlockchainInfo(result)
                    DispatchQueue.main.async {
                        openWindow(id: "BlockchainInfo")
                    }
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "server.rack")
        }
    }
    
    private func initialLoad() {
        selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        DataManager.retrieve(entityName: .bitcoinEnv) { env in
            guard let env = env else { return }
            let envValues = BitcoinEnvValues(dictionary: env)
            self.env = [
                "BINARY_NAME": envValues.binaryName,
                "VERSION": envValues.version,
                "PREFIX": envValues.prefix,
                "DATADIR": Defaults.shared.bitcoinDataDir,
                "CHAIN": envValues.chain
            ]
            isBitcoinCoreRunning()
        }
    }
    
    private func isBitcoinCoreRunning() {
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            guard error == nil, let _ = result as? [String: Any] else {
                return
            }
            isRunning = true
        }
    }
}
