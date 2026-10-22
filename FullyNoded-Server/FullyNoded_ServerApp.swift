//
//  FullyNoded_ServerApp.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

@main
struct FullyNoded_ServerApp: App {
    
    @Environment(\.openWindow) var openWindow
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var isRunning = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var blockchainInfo: BlockchainInfo?
    
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
                    // Nostr Connect: relay and bridge back on if they were.
                    NostrConnectModel.shared.startIfConfigured()
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
        Window("Utilities", id: "Utilities-JM") {
            JMUtilsView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("QuickConnect", id: "QuickConnect-JM") {
            JMQuickConnectView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Utilities", id: "Utilities") {
            BtcUtilsView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Utilities", id: "Utilities-Knots") {
            KnotsUtilsView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("QuickConnect", id: "QuickConnect") {
            QuickConnectView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        // Opened from the Setup Assistant (the sidebar page is the same view).
        Window("Nostr Connect", id: "NostrConnect") {
            NostrConnectView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Silent Payments", id: "SilentPayments") {
            SilentPaymentsView()
                .cypherPage()
                .cypherTheme()
        }
        .handlesExternalEvents(matching: [])
        Window("Blockchain Info", id: "BlockchainInfo") {
            if let blockchainInfo = blockchainInfo {
                BlockchainInfoView(blockchainInfo: blockchainInfo)
                    .cypherPage()
                    .cypherTheme()
            }
        }
        .handlesExternalEvents(matching: [])
        Window("Silent Payment History", id: "SPHistory") {
            SPHistoryView()
                .cypherPage()
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
