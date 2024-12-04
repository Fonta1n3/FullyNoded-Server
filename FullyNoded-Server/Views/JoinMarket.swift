//
//  JoinMarket.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import SwiftUI

struct JoinMarket: View {
    @Environment(\.openURL) var openURL
    @State private var walletName = ""
    @State private var gapLimit = ""
    @State private var promptToIncreaseGapLimit = false
    @State private var version = UserDefaults.standard.string(forKey: "tagName") ?? ""
    @State private var qrImage: NSImage? = nil
    @State private var startCheckingIfRunning = false
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var logOutput = ""
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var url: String?
    @State private var isAutoRefreshing = false
    @State private var orderBookOpened = false
    private let timerForStatus = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private var chains = ["main", "test", "signet", "regtest"]
    
    
    var body: some View {
        FNIcon()
        VStack() {
            HStack() {
                Image(systemName: "server.rack")
                    .padding(.leading)
                
                Text("Join Market Server v\(version)")
                Spacer()
                
                Button {
                    isAutoRefreshing = false
                    isJoinMarketRunning()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .padding([.trailing])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                if isAnimating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding([.leading])
                }
                if isRunning {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                            .padding([.leading])
                        
                        Text("Starting...")
                            .onAppear {
                                isAutoRefreshing = true
                            }
                        
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .padding([.leading])
                        
                        Text("Running")
                            .onAppear {
                                isAutoRefreshing = true
                            }
                    }
                    
                } else {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                            .padding([.leading])
                        
                        Text("Starting...")
                            
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .padding([.leading])
                        Text("Stopped")
                    }
                    
                }
                if !isRunning {
                    Button {
                        startJoinMarket()
                    } label: {
                        Text("Start")
                    }
                } else {
                    Button {
                        stopJoinMarket()
                    } label: {
                        Text("Stop")
                    }
                }
                EmptyView()
                    .onReceive(timerForStatus) { _ in
                        isJoinMarketRunning()
                    }
            }
            .padding([.leading])
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
        
        VStack() {
            Label("Network", systemImage: "network")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(selectedChain)
                .padding([.leading])
                .padding(.leading)
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
                    increaseGapLimit()
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
        
        VStack() {
            Label("Quick Connect", systemImage: "qrcode")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Connect Fully Noded - Join Market", systemImage: "qrcode") {
                showConnectUrls()
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let qrImage = qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    .onAppear {
                        hideQrData()
                    }
                if let url = url {
                    Link("Connect Fully Noded - Join Market (locally)", destination: URL(string: url)!)
                        .padding([.leading, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .trailing])
        )
        
        Spacer()
        .onAppear(perform: {
            initialLoad()
        })
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
    }
    
    private func hideQrData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.qrImage = nil
            self.url = nil
        }
    }
    
    private func initialLoad() {
        env["TAG_NAME"] = UserDefaults.standard.string(forKey: "tagName") ?? ""
        selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        isJoinMarketRunning()
    }
    
    private func openDataDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Users/\(NSUserName())/Library/Application Support/joinmarket")
    }
    
    private func orderBook() {
        orderBookOpened = true
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
    
    private func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func updateConf(key: String, value: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        guard fileExists(path: jmConfPath) else { return }
        guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)) else {
            print("no jm conf")
            return
        }
        guard let string = String(data: conf, encoding: .utf8) else {
            print("cant get string")
            return
        }
        let arr = string.split(separator: "\n")
        for item in arr {
            let uncommentedKey = key.replacingOccurrences(of: "#", with: "")
            if item.hasPrefix("\(key) =") {
                let newConf = string.replacingOccurrences(of: item, with: uncommentedKey + " = " + value)
                if (try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)) == nil {
                    print("failed writing to jm config")
                } else {
                    print("wrote to joinmarket.cfg")
                }
            }
        }
    }
    
    private func showConnectUrls() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            showMessage(message: "No hostnames.")
            return
        }
        let host = hiddenServices[0] + ":" + "28183"
        
        let certPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/ssl/cert.pem"
        if FileManager.default.fileExists(atPath: certPath) {
            guard var cert = try? String(contentsOf: URL(fileURLWithPath: certPath)) else {
                showMessage(message: "No joinmarket cert.")
                return
            }
            cert = cert.replacingOccurrences(of: "\n", with: "")
            cert = cert.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: " ", with: "")
            let quickConnectUrl = "http://" + host + "?cert=\(cert.urlSafeB64String)"
            self.url = "joinmarket://localhost:28183?cert=\(cert.urlSafeB64String)"
            qrImage = quickConnectUrl.qrQode
        }
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
        
    private func startJoinMarket() {
        isAnimating = true
        // Ensure Bitcoin Core is running before starting JM.
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            guard error == nil, let result = result as? [String: Any] else {
                if let error = error {
                    if error.contains("Could not connect to the server") {
                        isAnimating = false
                        showMessage(message: "Looks like Bitcoin Core is not running. Please start Bitcoin Core and try again.")
                    } else {
                        startNow()
                    }
                }
                return
            }
            startNow()
        }
    }
    
    private func startNow() {
        removeLockFile()
        setEnv()
        launchJmStarter()
    }
    
    private func setEnv() {
        self.env["TAG_NAME"] = UserDefaults.standard.string(forKey: "tagName") ?? ""
    }
    
    private func launchJmStarter() {
        ScriptUtil.runScript(script: .launchJmStarter, env: self.env, args: nil) { (output, rawData, errorMessage) in
            isAnimating = false
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    // If attempting to start JM daemon when a .lock file is present in /Users/you/Library/Application Support/joinmarket will result
    // in an error.
    private func removeLockFile() {
        let fm = FileManager.default
        let path = "/Users/\(NSUserName())/Library/Application Support/joinmarket/wallets"

        if let wallets = try? fm.contentsOfDirectory(atPath: path) {
            for wallet in wallets {
                if wallet.hasSuffix(".lock") {
                    // Delete the .lock file
                    try? fm.removeItem(atPath: path + "/" + wallet)
                }
            }
        }
    }
    
    private func stopJoinMarket() {
        ScriptUtil.runScript(script: .stopJm, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
        
    private func isJoinMarketRunning() {
        if !isAutoRefreshing {
            isAnimating = true
            isAutoRefreshing = true
        }
        JMRPC.sharedInstance.command(method: .session, param: nil) { (response, errorDesc) in
            isAnimating = false
            guard errorDesc == nil else {
                if errorDesc!.contains("Could not connect to the server.") {
                    isRunning = false
                } else if !errorDesc!.contains("The request timed out.") {
                    showMessage(message: errorDesc!)
                }
                return
            }
            guard let _ = response as? [String:Any] else {
                isRunning = false
                return
            }
            isRunning = true
            
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
}

#Preview {
    JoinMarket()
}
