//
//  BitcoinCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI


struct BitcoinCore: View {
    
    @State private var qrImage: NSImage? = nil
    @State private var startCheckingIfRunning = false
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var logOutput = ""
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var fullyNodedUrl: String?
    @State private var unifyUrl: String?
    private let timerForBitcoinStatus = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var chains = ["main", "test", "signet", "regtest"]
    
    
    var body: some View {
        HStack() {
            Image(systemName: "server.rack")
                .padding(.leading)
            Text("Bitcoin Core Server")
            Spacer()
            Button {
                isBitcoinCoreRunning()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .padding([.trailing])
        }
        .padding([.top])
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
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .padding([.leading])
                }
                Text("Running")
            } else {
                if isAnimating {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                        .padding([.leading])
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.red)
                        .padding([.leading])
                }
                Text("Stopped")
            }
            if !isRunning {
                Button {
                    startBitcoinCore()
                } label: {
                    Text("Start")
                }
            } else {
                Button {
                    stopBitcoinCore()
                } label: {
                    Text("Stop")
                }
            }
            EmptyView()
                .onReceive(timerForBitcoinStatus) { _ in
                    isBitcoinCoreRunning()
                }
        }
        .padding([.leading, .bottom])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Network", systemImage: "network")
            .padding(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack() {
            Picker("", selection: $selectedChain) {
                ForEach(chains, id: \.self) {
                    Text($0)
                }
            }
            .onChange(of: selectedChain) {
                updateChain(chain: selectedChain)
                isBitcoinCoreRunning()
            }
            //.padding([.trailing])
            .frame(width: 150)
            //.clipped()
            //.contentShape(Rectangle())
            //.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding([.leading, .trailing, .bottom])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Utilities", systemImage: "wrench.and.screwdriver")
            .padding(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack() {
            Button {
                runScript(script: .launchVerifier)
            } label: {
                Text("Verify")
            }
            .padding(.leading)
            Button {
                print("update")
            } label: {
                Text("Update")
            }
            Button {
                openFile(file: "bitcoin.conf")
            } label: {
                Text("bitcoin.conf")
            }
            Button {
                openFile(file: "debug.log")
            } label: {
                Text("Log")
            }
            Button {
                refreshRPCAuth()
            } label: {
                Text("Refresh RPC Authentication")
            }
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Quick Connect", systemImage: "qrcode")
            .padding([.leading, .top])
            .frame(maxWidth: .infinity, alignment: .leading)
        
        Button("Connect Fully Noded", systemImage: "qrcode") {
            connectFN()
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        if let qrImage = qrImage {
            Image(nsImage: qrImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                .onAppear {
                    setSensitiveDataToNil()
                }
        }
        
        if let fullyNodedUrl = fullyNodedUrl {
            Link("Connect Fully Noded", destination: URL(string: fullyNodedUrl)!)
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        if let unifyUrl = unifyUrl {
            Link("Connect Unify", destination: URL(string: unifyUrl)!)
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        Spacer()
        
        HStack() {
            Label(logOutput, systemImage: "info.circle")
                .padding(.all)
        }
        .onAppear(perform: {
            initialLoad()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func refreshRPCAuth() {
        guard let creds = RPCAuth().generateCreds(username: "FullyNoded-Server", password: nil) else { return }
        guard let dataDir = env["DATADIR"] else { return }
        let bitcoinConfPath = dataDir + "/bitcoin.conf"
        if FileManager.default.fileExists(atPath: bitcoinConfPath) {
            guard let conf = try? Data(contentsOf: URL(fileURLWithPath: bitcoinConfPath)),
                    let string = String(data: conf, encoding: .utf8) else {
                print("no conf")
                return
            }
            let newConf = """
            \(creds.rpcAuth)
            \(string)
            """
            try? newConf.write(to: URL(fileURLWithPath: bitcoinConfPath), atomically: false, encoding: .utf8)
            let passData = Data(creds.rpcPassword.utf8)
            guard let encryptedPass = Crypto.encrypt(passData) else { return }
            DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: "BitcoinRPCCreds") { updated in
                guard updated else { return }
                runScript(script: .killBitcoind)
            }
        }
    }
    
    private func setSensitiveDataToNil() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.qrImage = nil
            self.fullyNodedUrl = nil
            self.unifyUrl = nil
        }
    }
    
    private func initialLoad() {
        selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        DataManager.retrieve(entityName: "BitcoinEnv") { env in
            guard let env = env else { return }
            let envValues = BitcoinEnvValues(dictionary: env)
            self.env = [
                "BINARY_NAME": envValues.binaryName,
                "VERSION": envValues.version,
                "PREFIX": envValues.prefix,
                "DATADIR": envValues.dataDir,
                "CHAIN": envValues.chain
            ]
            isBitcoinCoreRunning()
        }
    }
    
    private func connectFN() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            print("no hostnames")
            return
        }
        var onionHost = ""
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "signet"
        
         switch chain {
         case "main":
             onionHost = hiddenServices[1] + ":" + "8332"
         case "test":
             onionHost = hiddenServices[2] + ":" + "18332"
         case "signet":
             onionHost = hiddenServices[3] + ":" + "38332"
         case "regtest":
             onionHost = hiddenServices[3] + ":" + "18443"
         default:
             break
         }
        
        DataManager.retrieve(entityName: "BitcoinRPCCreds") { rpcCred in
            guard let rpcCred = rpcCred, let encryptedPass = rpcCred["password"] as? Data else {
                print("no passwrod")
                return
            }
            
            guard let decryptedPass = Crypto.decrypt(encryptedPass) else {
                print("cant decrypt")
                return
            }
            
            guard let rpcPass = String(data: decryptedPass, encoding: .utf8) else {
                print("cant convert")
                return
            }
            
            let url = "http://FullyNoded-Server:\(rpcPass)@\(onionHost)"
            qrImage = url.qrQode
            
            let port = UserDefaults.standard.object(forKey: "port") as? String ?? "38332"
            self.fullyNodedUrl = "btcrpc://FullyNoded-Server:\(rpcPass)@localhost:\(port)"
            self.unifyUrl = "unify://FullyNoded-Server:\(rpcPass)@localhost:\(port)"
        }
    }
    
    private func openFile(file: String) {
        let d = Defaults.shared.dataDir
        let env = ["FILE": "\(d)/\(file)"]
        openConf(script: .openFile, env: env, args: []) { _ in }
    }
    
    private func updateChain(chain: String) {
        var port = "8332"
        switch chain {
        case "signet": port = "38332"
        case "regtest": port = "18443"
        case "test": port = "18332"
        default: port = "8332"
        }
        UserDefaults.standard.setValue(port, forKey: "port")
        UserDefaults.standard.setValue(chain.lowercased(), forKey: "chain")
        self.env["CHAIN"] = chain
        DataManager.update(keyToUpdate: "chain", newValue: chain, entity: "BitcoinEnv") { updated in
            guard updated else {
                showMessage(message: "There was an issue updating your network...")
                return
            }
            isBitcoinCoreRunning()
        }
        updateLightningConfNetwork(chain: chain)
        updateJMConfNetwork(chain: chain)
        
    }
    
    private func updateJMConfNetwork(chain: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        if FileManager.default.fileExists(atPath: jmConfPath) {
            // get the config
            
            guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)),
                    let string = String(data: conf, encoding: .utf8) else {
                print("no jm conf")
                return
            }
            let arr = string.split(separator: "\n")
            guard arr.count > 0  else { return }
            for item in arr {
                if item.hasPrefix("network = ") {
                    let existingNetworkArr = item.split(separator: " = ")
                    if existingNetworkArr.count == 2 {
                        let existingNetwork = existingNetworkArr[1]
                        var network = chain
                        if network == "regtest" {
                            network = "testnet"
                        }
                        let newConf = string.replacingOccurrences(of: existingNetwork, with: network)
                        try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
                    }
                }
            }
        }
    }
    
    private func updateLightningConfNetwork(chain: String) {
        let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
        if FileManager.default.fileExists(atPath: lightningConfPath) {
            // get the config
            
            guard let conf = try? Data(contentsOf: URL(fileURLWithPath: lightningConfPath)),
                    let string = String(data: conf, encoding: .utf8) else {
                print("no conf")
                return
            }
            let arr = string.split(separator: "\n")
            guard arr.count > 0  else { return }
            for item in arr {
                if item.hasPrefix("network=") {
                    let existingNetworkArr = item.split(separator: "=")
                    if existingNetworkArr.count == 2 {
                        let existingNetwork = existingNetworkArr[1]
                        var network = chain
                        if network == "main" {
                            network = "bitcoin"
                        }
                        let newConf = string.replacingOccurrences(of: existingNetwork, with: network)
                        try? newConf.write(to: URL(fileURLWithPath: lightningConfPath), atomically: false, encoding: .utf8)
                    }
                }
            }
        }
    }
    
    private func startBitcoinCore() {
        isAnimating = true
        runScript(script: .startBitcoin)
    }
    
    private func startBitcoinParse(result: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.runScript(script: .didBitcoindStart)
        }
    }
    
    private func parseDidBitcoinStart(result: String) {
        if !result.contains("Stopped") {
            isBitcoinCoreRunning()
        }
        startCheckingIfRunning = true
    }
    
    private func stopBitcoinCore() {
        isAnimating = true
        BitcoinRPC.shared.command(method: "stop", params: [:]) { (result, error) in
            guard let result = result as? String else {
                isAnimating = false
                showMessage(message: error ?? "Unknown issue turning off Bitcoin Core.")
                return
            }
            
            self.showBitcoinLog()
            self.stopBitcoinParse(result: result)
        }
    }
    
    private func stopBitcoinParse(result: String) {
        isAnimating = false
        if result.contains("Bitcoin Core stopping") {
            isRunning = false
        } else {
            isRunning = true
            showMessage(message: "Error turning off mainnet")
        }
    }
    
    
    private func showBitcoinLog() {
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "signet"
        var path:URL?
        
        switch chain {
        case "main":
            path = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Application Support/Bitcoin/debug.log")
        case "test":
            path = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Application Support/Bitcoin/testnet3/debug.log")
        case "regtest":
            path = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Application Support/Bitcoin/regtest/debug.log")
        case "signet":
            path = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Application Support/Bitcoin/signet/debug.log")
        default:
            break
        }
        
        guard let path = path, let log = try? String(contentsOf: path, encoding: .utf8) else {
            print("can not get \(chain) debug.log")
            return
        }
        
        let logItems = log.components(separatedBy: "\n")
        
        DispatchQueue.main.async {
            if logItems.count > 2 {
                let lastLogItem = "\(logItems[logItems.count - 2])"
                logOutput = lastLogItem
                if lastLogItem.contains("Shutdown: done") {
                    isRunning = false
                }
                if lastLogItem.contains("ThreadRPCServer incorrect password") {
                    showMessage(message: lastLogItem)
                }
            }
        }
    }
    
    private func isBitcoinCoreRunning() {
        isAnimating = true
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            isAnimating = false
            guard error == nil else {
                if let error = error {
                    if !error.contains("Could not connect to the server") {
                        isRunning = true
                        switch error {
                        case _ where error.contains("Loading block index"),
                            _ where error.contains("Verifying blocks"),
                            _ where error.contains("Loading P2P addresses…"),
                            _ where error.contains("Pruning"),
                            _ where error.contains("Rewinding"),
                            _ where error.contains("Rescanning"),
                            _ where error.contains("Loading wallet"),
                            _ where error.contains("Looks like your rpc credentials"):
                            logOutput = error
                        default:
                            showMessage(message: error)
                        }
                    } else {
                        isRunning = false
                        logOutput = error
                    }
                }
                return
            }
            isRunning = true
            showBitcoinLog()
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func runScript(script: SCRIPT) {
        #if DEBUG
        print("run script: \(script.stringValue)")
        #endif
        
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            let resource = script.stringValue
            guard let path = Bundle.main.path(forResource: resource, ofType: "command") else { return }
            let stdOut = Pipe()
            let stdErr = Pipe()
            let task = Process()
            task.launchPath = path
            task.environment = env
            task.standardOutput = stdOut
            task.standardError = stdErr
            task.launch()
            task.waitUntilExit()
            let data = stdOut.fileHandleForReading.readDataToEndOfFile()
            let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
            var result = ""
            
            if let output = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("output: \(output)")
                #endif
                result += output
            }
            
            if let errorOutput = String(data: errData, encoding: .utf8) {
                #if DEBUG
                print("error: \(errorOutput)")
                #endif
                result += errorOutput
                if errorOutput != "" {
                    showMessage(message: errorOutput)
                }
            }
            
            parseScriptResult(script: script, result: result)
        }
    }
    
    func parseScriptResult(script: SCRIPT, result: String) {
        switch script {
        case .startBitcoin:
            showBitcoinLog()
            startBitcoinParse(result: result)
            
        case .didBitcoindStart:
            parseDidBitcoinStart(result: result)
            
        case .killBitcoind:
            if result.contains("Its dead") {
                isRunning = false
                showMessage(message: "RPC Authentication refreshed, you need to start your node for the changes to take effect.")
            }
            
        default:
            break
        }
    }
    
    private func openConf(script: SCRIPT, env: [String:String], args: [String], completion: @escaping ((Bool)) -> Void) {
        let resource = script.stringValue
        guard let path = Bundle.main.path(forResource: resource, ofType: "command") else {
            return
        }
        let stdOut = Pipe()
        let task = Process()
        task.launchPath = path
        task.environment = env
        task.arguments = args
        task.standardOutput = stdOut
        task.launch()
        task.waitUntilExit()
        let data = stdOut.fileHandleForReading.readDataToEndOfFile()
        var result = ""
        if let output = String(data: data, encoding: .utf8) {
            result += output
            completion(true)
        } else {
            completion(false)
        }
    }
}
