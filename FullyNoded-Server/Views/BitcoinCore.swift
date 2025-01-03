//
//  BitcoinCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI


struct BitcoinCore: View {
    
    @State private var isBooting = true
    @State private var statusText = ""
    @State private var promptToRefreshRpcAuth = false
    @State private var rpcAuth = ""
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
       FNIcon()
        VStack() {
            
            HStack() {
                Image(systemName: "server.rack")
                    .padding(.leading)
                if let version = env["VERSION"] {
                    Text("Bitcoin Core Server v\(version)")
                } else {
                    Text("Bitcoin Core Server")
                }
                if let blockchainInfo = blockchainInfo, blockchainInfo.initialblockdownload {
                    Label {
                        Text("Downloading the blockchain...")
                            .foregroundStyle(.secondary)
                    } icon: {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
                Spacer()
                Button {
                    isBitcoinCoreRunning()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .padding([.trailing])
            }
            .padding([.leading, .trailing])
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
                        Text(statusText)
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .padding([.leading])
                        Text("Running")
                    }
                   
                } else {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                            .padding([.leading])
                        Text(statusText)
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .padding([.leading])
                        Text("Stopped")
                    }
                   
                }
                if !isRunning, !isAnimating {
                    Button {
                        startBitcoinCore()
                    } label: {
                        Text("Start")
                    }
                } else if !isAnimating {
                    Button {
                        stopBitcoinCore()
                    } label: {
                        Text("Stop")
                    }
                }
                
                if let blockchainInfo = blockchainInfo {
                    if blockchainInfo.progressString == "Fully verified" {
                        Label {
                            Text(blockchainInfo.progressString)
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Label {
                            Text(blockchainInfo.progressString)
                        } icon: {
                            Image(systemName: "xmark.seal")
                                .foregroundStyle(.orange)
                        }
                    }
                    Label {
                        Text("Blockheight " + "\(blockchainInfo.blockheight)")
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
                
                EmptyView()
                    .onReceive(timerForBitcoinStatus) { _ in
                        isBitcoinCoreRunning()
                    }
            }
            .padding([.leading, .bottom])
            .frame(maxWidth: .infinity, alignment: .leading)
            
        }
        .padding([.top])
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .trailing])
        )
        
        
        VStack() {
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
            Label("Utilities", systemImage: "wrench.and.screwdriver")
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                Button {
                    verify()
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
                   promptToRefreshRpcAuth = true
                } label: {
                    Text("Refresh RPC Authentication")
                }
                Button {
                    openDataDir()
                } label: {
                    Text("Data Dir")
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
            HStack() {
                Label("Quick Connect", systemImage: "qrcode")
                    .padding([.leading])
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button {
                    showMessage(message: "The Quick Connect QR exports your rpc hostname (an onion or localhost) and the rpc port (combined these make up your nodes rpc address) which is required for FN to connect.\n\nThis QR does *NOT* include the FN-Server RPC credentials (it includes a dummy rpc user and password for security).\n\nYou must export and authorize your rpc user from FN mobile apps to FN-Server to complete your connection.\n\nTo do this: In FN navigate to Node Manager > + > Scan QR > update the rpc password in Node Credentials > Save the node > Export the rpcauth text from FN and use the below text field to add it to your bitcoin.conf.")
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .padding([.trailing])
            }
            
            
            Button("Connect Fully Noded", systemImage: "qrcode") {
                connectFN()
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            
            HStack() {
                Text("Authorize an additional RPC user:")
                    .padding([.leading])
                TextField("rpcauth=FullyNoded:xxxx$xxxx", text: $rpcAuth)
                    .padding([])
                if rpcAuth != "" {
                    Button {
                        if addRpcAuthToConf() {
                            rpcAuth = ""
                            showMessage(message: "RPC user authorized. You will need to restart your node for the change to take effect.")
                        }
                    } label: {
                        Text("Add RPC auth")
                    }
                }
                Spacer()
            }
            
            if let qrImage = qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
            }
            
            if let fullyNodedUrl = fullyNodedUrl {
                Link("Connect Fully Noded (locally)", destination: URL(string: fullyNodedUrl)!)
                    .padding([.leading])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if let unifyUrl = unifyUrl {
                Link("Connect Unify (locally)", destination: URL(string: unifyUrl)!)
                    .padding([.leading, .bottom])
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        
        Label {
            Text(logOutput)
        } icon: {
            Image(systemName: "info.circle")
        }
        .padding(.all)
        .foregroundStyle(.tertiary)
        
        .onAppear(perform: {
            initialLoad()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("This starts Bitcoin Core with the -reindex flag. This action will delete the entire existing blockchain and download it again, are you sure you want to proceed? (it can take a long time!)", isPresented: $promptToReindex) {
            Button("Reindex now", role: .destructive) {
                reindex()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("This action updates your exisiting FullyNoded-Server rpcuser with a new rpc password as well as the Core Lightning config (if present) and Join Market config (if present). FN-Server will attempt to shut down Bitcoin Core so that the changes take effect. Do you wish to proceed?", isPresented: $promptToRefreshRpcAuth) {
            Button("Refresh", role: .destructive) {
                refreshRPCAuth()
            }
            Button("Cancel", role: .cancel) {}
        }
        
    }
    
    private func reindex() {
        if !isRunning {
            isAnimating = true
            statusText = "Reindexing..."
            ScriptUtil.runScript(script: .reindex, env: env, args: nil) { (_, _, errorMessage) in
                statusText = ""
                guard errorMessage == nil else {
                    if errorMessage != "" {
                        showMessage(message: errorMessage!)
                    }
                    return
                }
                showMessage(message: "Reindex initiated, this can take awhile..")
            }
        } else {
            showMessage(message: "Bitcoin Core must stopped before redindexing.")
        }
    }
    
    private func openDataDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Defaults.shared.dataDir)
    }
    
    private func verify() {
        ScriptUtil.runScript(script: .launchVerifier, env: env, args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else {
                    
                }
                return
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
        guard let newCreds = RPCAuth().generateCreds(username: "FullyNoded-Server", password: nil) else {
            showMessage(message: "Unable to create rpc creds.")
            return
        }
        
        guard let conf = bitcoinConf() else {
            showMessage(message: "Unable to get the existing bitcoin.conf file.")
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
        
        guard writeBitcoinConf(newConf: newConf) else {
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
        
        DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: .rpcCreds) { updated in
            guard updated else {
                showMessage(message: "BitcoinRPCCreds update failed")
                return
            }
            ScriptUtil.runScript(script: .killBitcoind, env: env, args: nil) { (output, rawData, errorMessage) in
                guard errorMessage == nil else {
                    showMessage(message: errorMessage!)
                    return
                }
                guard let output = output else {
                    showMessage(message: "No output when killing Bitcoin Core, you can probably ignore this error. RPC credentials should be updated, ensure Bitcoin Core restarts for the changes to take place.")
                    return
                }
                parseScriptResult(script: .killBitcoind, result: output)
            }
        }
    }
    
    private func bitcoinConfPath() -> String {
        let dataDir = Defaults.shared.dataDir
        return dataDir + "/bitcoin.conf"
    }
    
    private func bitcoinConf() -> String? {
        return conf(stringPath: bitcoinConfPath())
    }
    
    private func writeBitcoinConf(newConf: String) -> Bool {
        return ((try? newConf.write(to: URL(fileURLWithPath: bitcoinConfPath()), atomically: false, encoding: .utf8)) != nil)
    }
    
    private func addRpcAuthToConf() -> Bool {
        guard let conf = bitcoinConf() else {
            return false
        }
        
        let newConf = """
            \(rpcAuth)
            \(conf)
            """
        
        guard writeBitcoinConf(newConf: newConf) else {
            showMessage(message: "Can not write the new conf.")
            return false
        }
        
        return true
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
                "DATADIR": Defaults.shared.dataDir,
                "CHAIN": envValues.chain
            ]
            isBitcoinCoreRunning()
        }
    }
    
    private func connectFN() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            showMessage(message: "No hostnames. Please report this.")
            return
        }
        var onionHost = ""
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        
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
        
        DataManager.retrieve(entityName: .rpcCreds) { rpcCred in
            guard let _ = rpcCred else {
                showMessage(message: "No rpc credentials saved.")
                return
            }
            
//            guard let decryptedPass = Crypto.decrypt(encryptedPass) else {
//                showMessage(message: "Unable to decrypt rpc password data.")
//                return
//            }
            
//            guard let rpcPass = String(data: decryptedPass, encoding: .utf8) else {
//                showMessage(message: "Unable to encode decrypted rpc data to utf8 string.")
//                return
//            }
            
            let url = "http://xxx:xxx@\(onionHost)"
            qrImage = url.qrQode
            
            let port = UserDefaults.standard.object(forKey: "port") as? String ?? "8332"
            self.fullyNodedUrl = "btcrpc://xxx:xxx@localhost:\(port)"
            self.unifyUrl = "unify://xxx:xxx@localhost:\(port)"
        }
    }
    
    private func openFile(file: String) {
        ScriptUtil.runScript(script: .openFile, env: ["FILE": "\(file)"], args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
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
        DataManager.update(keyToUpdate: "chain", newValue: chain, entity: .bitcoinEnv) { updated in
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
        if fileExists(path: jmConfPath) {
            guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)),
                    let string = String(data: conf, encoding: .utf8) else {
                showMessage(message: "No Join Market config found.")
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
                        if network == "main" {
                            network = "mainnet"
                        }
                        let newConf = string.replacingOccurrences(of: item, with: "network = \(network)")
                        try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
                    }
                }
            }
        }
    }
    
    private func updateLightningConfNetwork(chain: String) {
        let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
        if fileExists(path: lightningConfPath) {
            guard let conf = try? Data(contentsOf: URL(fileURLWithPath: lightningConfPath)),
                    let string = String(data: conf, encoding: .utf8) else {
                return
            }
            let arr = string.split(separator: "\n")
            guard arr.count > 0  else { return }
            for item in arr {
                if item.hasPrefix("network=") {
                    let existingNetworkArr = item.split(separator: "=")
                    if existingNetworkArr.count == 2 {
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
        isBooting = true
        statusText = "Starting.."
        ScriptUtil.runScript(script: .startBitcoin, env: env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else {
                    
                }
                return
            }
            guard let output = output else { return }
            parseDidBitcoinStart(result: output)
        }
    }
    
    private func startBitcoinParse(result: String) {
        var interval = 10.0
        if isBooting {
            interval = 3.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            ScriptUtil.runScript(script: .didBitcoindStart, env: env, args: nil) { (output, rawData, errorMessage) in
                guard errorMessage == nil else {
                    if errorMessage != "" {
                        showMessage(message: errorMessage!)
                    } else {
                        
                    }
                    return
                }
                guard let output = output else { return }
                parseScriptResult(script: .didBitcoindStart, result: output)
            }
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
        statusText = "Stopping..."
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
        statusText = "Refreshing..."
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            isBooting = false
            isAnimating = false
            guard error == nil, let result = result as? [String: Any] else {
                if let error = error {
                    handleRPCError(error: error)
                }
                return
            }
            
            let blockchainInfo = BlockchainInfo(result)
            self.blockchainInfo = blockchainInfo
            isRunning = true
            showBitcoinLog()
        }
    }
    
    private func handleRPCError(error: String) {
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
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
        
    func parseScriptResult(script: SCRIPT, result: String) {
        switch script {
        case .startBitcoin:
            showBitcoinLog()
            startBitcoinParse(result: result)
            
        case .didBitcoindStart:
            parseDidBitcoinStart(result: result)
            
        case .killBitcoind:
            if result.contains("Its dead") || result.contains("Does not exist") {
                isRunning = false
                showMessage(message: "RPC Authentication refreshed, you need to start your node for the changes to take effect.")
            }
            
        default:
            break
        }
    }
}
