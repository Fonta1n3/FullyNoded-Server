//
//  JMUtilsView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/6/25.
//

import SwiftUI

struct JMUtilsView: View {
    
    @Environment(\.openURL) var openURL
    @State private var showError = false
    @State private var message = ""
    @State private var env: [String: String] = [:]
    @State private var promptToReindex = false
    @State private var isAnimating = false
    @State private var promptToIncreaseGapLimit = false
    @State private var orderBookOpened = false
    @State private var walletName = ""
    @State private var gapLimit = ""
    
    var body: some View {
        Spacer()
        VStack() {
            Label("Utilities", systemImage: "wrench.and.screwdriver")
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                Button {
                    openFile(file: "joinmarket.cfg")
                } label: {
                    Text("joinmarket.cfg")
                }
                Button {
                    configureJm()
                } label: {
                    Text("Configure JM")
                }
                Button {
                    openDataDir()
                } label: {
                    Text("Data Dir")
                }
                Button {
                    promptToIncreaseGapLimit = true
                } label: {
                    Text("Increase gap limit")
                }
                Button {
                    rescan()
                } label: {
                    Text("Rescan")
                }
                Button {
                    orderBook()
                } label: {
                    Text("Order Book")
                }
                
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .trailing])
        )
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Increase the gap limit to? (upon completion a rescan will be required).", isPresented: $promptToIncreaseGapLimit) {
            TextField("Enter the new gap limit", text: $gapLimit)
            TextField("Enter the wallet name", text: $walletName)
            Button("OK", action: increaseGapLimit)
        }
        .alert("The order book launches a terminal (see output if any issues and report) and opens the browser at http://localhost:62601 to display the current order book.", isPresented: $orderBookOpened) {
            Button("Open", action: openOrderBookNow)
        }
        Spacer()
        Spacer()
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func openOrderBookNow() {
        ScriptUtil.runScript(script: .launchObWatcher, env: self.env, args: nil) { (output, _, errorMessage) in
            guard let errorMess = errorMessage, errorMess != "" else {
                openURL(URL(string: "http://localhost:62601")!)
                return
            }
            showMessage(message: errorMess)
        }
    }
    
    private func increaseGapLimit() {
        let env: [String: String] = ["TAG_NAME": env["TAG_NAME"]!, "GAP_AMOUNT": gapLimit, "WALLET_NAME": walletName]
        ScriptUtil.runScript(script: .launchIncreaseGapLimit, env: env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
            showMessage(message: "Gap limit increased, check the script output to be sure.")
        }
    }
    
    private func orderBook() {
        orderBookOpened = true
    }
    
    private func rescan() {
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            guard error == nil, let result = result as? [String: Any] else {
                showMessage(message: error ?? "Unknown error getblbockchaininfo.")
                return
            }
            guard let pruneheight = result["pruneheight"] as? Int else {
                showMessage(message: "No pruneheight")
                return
            }
            
            BitcoinRPC.shared.command(method: "rescanblockchain", params: ["start_height": pruneheight]) { (result, error) in
                guard error == nil, let _ = result as? [String: Any] else {
                    showMessage(message: error ?? "Unknown error rescanblockchain.")
                    return
                }
            }
            // No response from core when initiating a rescan...
            showMessage(message: "Blockchain rescan started.")
        }
    }
    
    private func openDataDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Users/\(NSUserName())/Library/Application Support/joinmarket")
    }
    
    private func openFile(file: String) {
        let fileEnv = ["FILE": "/Users/\(NSUserName())/Library/Application Support/joinmarket/\(file)"]
        ScriptUtil.runScript(script: .openFile, env: fileEnv, args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    private func configureJm() {
        var chain = UserDefaults.standard.object(forKey: "chain") as? String ?? "main"
        let port = UserDefaults.standard.object(forKey: "port") as? String ?? "8332"
        switch chain {
        case "main": chain = "mainnet"
        case "regtest": chain = "testnet"
        case "test": chain = "testnet"
        default:
            break
        }
        updateConf(key: "tx_fees", value: "7000")//https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md
        updateConf(key: "network", value: chain)
        updateConf(key: "rpc_port", value: port)
        updateConf(key: "rpc_wallet_file", value: "jm_wallet")
        updateConf(key: "tor_control_host", value: "/Users/\(NSUserName())/Library/Caches/tor/cp")
        updateConf(key: "#max_cj_fee_abs", value: "\(Int.random(in: 2200...5000))")
        updateConf(key: "#max_cj_fee_rel", value: Double.random(in: 0.00199...0.00243).avoidNotation)
        updateConf(key: "max_cj_fee_abs", value: "\(Int.random(in: 2200...5000))")
        updateConf(key: "max_cj_fee_rel", value: Double.random(in: 0.00243...0.00421).avoidNotation)
        
        DataManager.retrieve(entityName: .rpcCreds) { rpcCreds in
            guard let rpcCreds = rpcCreds,
                    let encryptedPassword = rpcCreds["password"] as? Data,
                    let decryptedPass = Crypto.decrypt(encryptedPassword),
                  let stringPass = String(data: decryptedPass, encoding: .utf8) else {
                showMessage(message: "Unable to get rpc creds to congifure JM.")
                return
            }
            
            updateConf(key: "rpc_password", value: stringPass)
            updateConf(key: "rpc_user", value: "FullyNoded-Server")
            
            BitcoinRPC.shared.command(method: "createwallet", params: ["wallet_name": "jm_wallet", "descriptors": false]) { (result, error) in
                guard error == nil else {
                    if !error!.contains("Database already exists.") {
                        showMessage(message: error!)
                    } else {
                        showMessage(message: "Join Market configured ✓")
                    }
                
                    isAnimating = false
                    return
                }
                
                showMessage(message: "Join Market configured ✓")
                isAnimating = false
            }
        }
    }
    
    private func updateConf(key: String, value: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        guard fileExists(path: jmConfPath) else { return }
        guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)) else {
            return
        }
        guard let string = String(data: conf, encoding: .utf8) else {
            return
        }
        let arr = string.split(separator: "\n")
        for item in arr {
            let uncommentedKey = key.replacingOccurrences(of: "#", with: "")
            if item.hasPrefix("\(key) =") {
                let newConf = string.replacingOccurrences(of: item, with: uncommentedKey + " = " + value)
                try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
            }
        }
    }
    
    private func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
}

#Preview {
    JMUtilsView()
}
