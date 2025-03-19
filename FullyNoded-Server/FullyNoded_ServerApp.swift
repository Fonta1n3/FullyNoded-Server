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
    @State private var menuBarImageString: String = "server.rack"
    @State private var blockchainInfo: BlockchainInfo?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if UserDefaults.standard.value(forKey: "encKeyFullyNodedServer") as? String == nil {
                        UserDefaults.standard.setValue(Crypto.privKeyData().base64EncodedString(), forKey: "encKeyFullyNodedServer")
                    }
                    initialLoad()
                }
        }
        Window("Utilities", id: "Utilities-JM") {
            JMUtilsView()
        }
        Window("QuickConnect", id: "QuickConnect-JM") {
            JMQuickConnectView()
        }
        Window("Utilities", id: "Utilities") {
            BtcUtilsView()
        }
        Window("QuickConnect", id: "QuickConnect") {
            QuickConnectView()
        }
        Window("Blockchain Info", id: "BlockchainInfo") {
            if let blockchainInfo = blockchainInfo {
                BlockchainInfoView(blockchainInfo: blockchainInfo)
            }
        }
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
            if isRunning {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "server.rack")
            }
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
                "DATADIR": Defaults.shared.bitcoinCoreDataDir,
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
            menuBarImageString = "circle.fill"
        }
    }
}
