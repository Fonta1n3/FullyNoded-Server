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
    @State private var blockchainInfo: BlockchainInfo? = nil
    @State private var promptToReindex = false
    private let timerForBitcoinStatus = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var chains = ["main", "test", "signet", "regtest"]
    
    
    var body: some View {
        HStack() {
            Image(systemName: "server.rack")
                .padding(.leading)
            if let version = env["VERSION"] {
                Text("Bitcoin Core Server v\(version)")
            } else {
                Text("Bitcoin Core Server")
            }
            
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
        
        if let blockchainInfo = blockchainInfo {
            if blockchainInfo.progressString == "Fully verified" {
                Label {
                    Text(blockchainInfo.progressString)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label {
                    Text(blockchainInfo.progressString)
                } icon: {
                    Image(systemName: "xmark.seal")
                        .foregroundStyle(.orange)
                }
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Label {
                Text("Blockheight: " + "\(blockchainInfo.blockheight)")
            } icon: {
                Image(systemName: "square.stack.3d.up")
            }
            .padding([.leading, .bottom])
            .frame(maxWidth: .infinity, alignment: .leading)
        }
            
        
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
            .frame(width: 150)
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
                openFile(file: "\(Defaults.shared.dataDir)/bitcoin.conf")
            } label: {
                Text("bitcoin.conf")
            }
            if let debugPath = debugLogPath() {
                Button {
                    openFile(file: debugPath)
                } label: {
                    Text("debug.log")
                }
            }
            Button {
                refreshRPCAuth()
            } label: {
                Text("Refresh RPC Authentication")
            }
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Defaults.shared.dataDir)
            } label: {
                Text("Data")
            }
            if Defaults.shared.prune != 0 {
                Button {
                    promptToReindex = true
                } label: {
                    Text("Reindex")
                }
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
        .alert("This action will delete the entire blockchain and download it again, are you sure you want to proceed?", isPresented: $promptToReindex) {
            Button("Reindex now", role: .destructive) {
                if !isRunning {
                    isAnimating = true
                    runScript(script: .reindex)
                } else {
                    showMessage(message: "Bitcoin Core must stopped before redindexing.")
                }
            }
        }
    }
    
    private func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func conf(stringPath: String) -> String? {
        guard fileExists(path: stringPath) else {
            #if DEBUG
            print("file does not exists at: \(stringPath)")
            #endif
            return nil
        }
        
        let url = URL(fileURLWithPath: stringPath)
        if let conf = try? Data(contentsOf: url) {
            guard let string = String(data: conf, encoding: .utf8) else {
                showMessage(message: "Can not encode data as utf8 string.")
                return nil
            }
            return string
        } else if let conf = try? String(contentsOf: url) {
            return conf
        } else {
            showMessage(message: "No contents found.")
            return nil
        }
    }
    
    private func updateJMConf(key: String, value: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        guard let conf = conf(stringPath: jmConfPath) else { return }
        let arr = conf.split(separator: "\n")
        for item in arr {
            if item.hasPrefix("\(key) =") {
                let newConf = conf.replacingOccurrences(of: item, with: key + " = " + value)
                try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
            }
        }
    }
    
    private func updateCLNConfig(rpcpass: String) {
        let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
        guard let conf = conf(stringPath: lightningConfPath) else { return }
        let arr = conf.split(separator: "\n")
        for item in arr {
            if item.hasPrefix("bitcoin-rpcpassword=") {
                let newConf = conf.replacingOccurrences(of: item, with: "bitcoin-rpcpassword=" + rpcpass)
                try? newConf.write(to: URL(fileURLWithPath: lightningConfPath), atomically: false, encoding: .utf8)
            }
        }
    }
    
    private func refreshRPCAuth() {
        // First remove all "FullyNoded-Server" users from the bitcoin.conf
        guard let newCreds = RPCAuth().generateCreds(username: "FullyNoded-Server", password: nil) else {
            showMessage(message: "Unable to create rpc creds.")
            return
        }
        
        let dataDir = Defaults.shared.dataDir
        
        let bitcoinConfPath = dataDir + "/bitcoin.conf"
        
        guard let conf = conf(stringPath: bitcoinConfPath) else {
            return
        }
        
        var removeFullyNodedUser = conf
        let confArr = conf.split(separator: "\n")
        
        for item in confArr {
            if item.hasPrefix("rpcauth=FullyNoded-Server") {
                removeFullyNodedUser = removeFullyNodedUser.replacingOccurrences(of: item, with: "")
            }
        }
        
        removeFullyNodedUser = removeFullyNodedUser.replacingOccurrences(of: "^\\s*", with: "", options: .regularExpression)
        
        let newConf = """
            \(newCreds.rpcAuth)
            \(removeFullyNodedUser)
            """
        
        guard ((try? newConf.write(to: URL(fileURLWithPath: bitcoinConfPath), atomically: false, encoding: .utf8)) != nil) else {
            showMessage(message: "Can not write the new conf.")
            return
        }
        
        let passData = Data(newCreds.rpcPassword.utf8)
        
        updateJMConf(key: "rpc_password", value: newCreds.rpcPassword)
        updateCLNConfig(rpcpass: newCreds.rpcPassword)
        
        guard let encryptedPass = Crypto.encrypt(passData) else {
            showMessage(message: "Can't encrypt rpcpass data.")
            return
        }
        
        DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: "BitcoinRPCCreds") { updated in
            guard updated else {
                showMessage(message: "BitcoinRPCCreds update failed")
                return
            }
            runScript(script: .killBitcoind)
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
        selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "signet"
        DataManager.retrieve(entityName: "BitcoinEnv") { env in
            guard let env = env else { return }
            let envValues = BitcoinEnvValues(dictionary: env)
            self.env = [
                "BINARY_NAME": envValues.binaryName,
                "VERSION": envValues.version,
                "PREFIX": envValues.prefix,
                "DATADIR": Defaults.shared.dataDir,
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
        let env = ["FILE": "\(file)"]
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
        self.blockchainInfo = nil
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
                        let newConf = string.replacingOccurrences(of: item, with: "network=" + network)
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
        guard let debugPath = debugLogPath() else { return }
        
        let path = URL(fileURLWithPath: debugPath)
        
        guard let log = try? String(contentsOf: path, encoding: .utf8) else {
            print("can't get log, path: \(path)")
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
            }
        }
    }
    
    private func debugLogPath() -> String? {
        let chain = Defaults.shared.chain
        var debugLogPath: String?
        switch chain {
        case "main":
            debugLogPath = "\(Defaults.shared.dataDir)/debug.log"
        case "test":
            debugLogPath = "\(Defaults.shared.dataDir)/testnet3/debug.log"
        case "regtest":
            debugLogPath = "\(Defaults.shared.dataDir)/regtest/debug.log"
        case "signet":
            debugLogPath = "\(Defaults.shared.dataDir)/signet/debug.log"
        default:
            break
        }
        return debugLogPath
    }
    
    private func isBitcoinCoreRunning() {
        isAnimating = true
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            isAnimating = false
            guard error == nil, let result = result as? [String: Any] else {
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
            
            let blockchainInfo = BlockchainInfo(result)
            self.blockchainInfo = blockchainInfo
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
