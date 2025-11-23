//
//  BtcUtilsView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/7/25.
//

import SwiftUI

struct BtcUtilsView: View {
    @State private var promptToSelectWallet = false
    @State private var promptToDeleteWallet = false
    @State private var isShowingPicker = false
    @State private var walletToDeletePath: String?
    @State private var showError = false
    @State private var message = ""
    @State private var env: [String: String] = [:]
    @State private var promptToRefreshRpcAuth = false
    @State private var promptToReindex = false
    @State private var promptToMineRegtestBlocks = false
    //@State private var showDropdownAlert = false
    @State private var selectedWallet = ""
    @State private var wallets: [String] = []
    @State private var sheetID = UUID()
    @State private var isLoading = false
    @State private var showMiningAlert = false
    @State private var selectedBlocks = "100"
    
    let blockOptions = ["1", "10", "50", "100", "500", "1000"]
    
        
    var body: some View {
        Spacer()
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
                    openFile(file: "\(Defaults.shared.bitcoinCoreDataDir)/bitcoin.conf")
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
                Button {
                    promptToSelectWallet = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Delete a Wallet")
                }
                if env["CHAIN"] == "regtest" {
                    Button {
                        promptToMineRegtestBlocks = true
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.5)
                            }
                            Text(isLoading ? "Mining..." : "Mine regtest blocks")
                        }
                    }
                    .disabled(isLoading)
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
        .onAppear(perform: {
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
            }
        })
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
        .sheet(isPresented: $isShowingPicker) {
            WalletPicker(completion: { path in
                isShowingPicker = false
                guard let path = path else {
                    showMessage(message: "No path returned from your selection.")
                    return
                }
                // ensure it is in the correctdatadir
                guard path.hasPrefix(defaultPath) && !path.hasSuffix("wallets") else {
                    showMessage(message: "Looks like you are not attempting to delete a wallet directory or are attempting to delete more then one wallet, please be careful, double check you are selecting the correct directory and try again.")
                    return
                }
                // check contents of directory for a .dat
                guard ((try? hasFileWithExtension(in: path, fileExtension: "dat")) != nil) else {
                    showMessage(message: "Unable to verify the selected directory conatins a .dat file, not a valid Bitcoin wallet directory.")
                    return
                }
                
                walletToDeletePath = path
                promptToDeleteWallet = true
                
            }, defaultPath: defaultPath)
        }
        
        Spacer()
        Spacer()
        
            .alert("Delete \(walletToDeletePath ?? "")?\n\nAre you absolutely sure!?", isPresented: $promptToDeleteWallet) {
                if let _ = walletToDeletePath {
                    Button("Delete now", role: .destructive, action: deleteWallet)
                }
            }
            .alert("Please select a wallet directory to delete.", isPresented: $promptToSelectWallet) {
                Button("Select Wallet Directory", action: { isShowingPicker = true })
                Button("Cancel", role: .cancel, action: {})
                Text("Once deleted the wallet is gone forever!")
            }
            .alert("Start mining?", isPresented: $promptToMineRegtestBlocks) {
                Button("Select a wallet to mine to.", action: { chooseWalletToMineTo() })
                Button("Cancel", role: .cancel, action: {})
            } message: {
                Text("In order to test a wallet in regtest you need some bitcoins to send and receive, this makes it easy. 100 blocks will be mined in about 20 seconds. First you will need to select a wallet to mine to. 100 blocks are mined as it takes 100 confirmations before a coinbase utxo is spendable.")
            }
            .alert(message, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showMiningAlert) {
                MineBlocksSheet(
                    isPresented: $showMiningAlert,
                    selectedWallet: $selectedWallet,
                    selectedBlocks: $selectedBlocks,
                    wallets: wallets,
                    blockOptions: blockOptions,
                    onConfirm: {
                        mine(wallet: selectedWallet, numberOfBlocks: selectedBlocks)
                    }
                )
            }
            .onChange(of: wallets) {
                sheetID = UUID()
            }
    }
    
    private var defaultPath: String {
        let chain = Defaults.shared.chain
        let root = Defaults.shared.bitcoinCoreDataDir
        var url = root
        if chain != "main" {
            url += "/\(chain)/wallets"
        }
        return url
    }
    
    private func deleteWallet() {
        guard let walletToDeletePath = walletToDeletePath else {
            showMessage(message: "No path provided to delete...")
            return
        }
        
        do {
            try FileManager.default.removeItem(atPath: walletToDeletePath)
            showMessage(message: "Wallet deleted successfully at \(walletToDeletePath)")
        } catch {
            showMessage(message: "Error deleting directory: \(error)")
        }
    }
    
    private func chooseWalletToMineTo() {
        BitcoinRPC.shared.command(method: "listwallets", params: [:]) { (result, error) in
            guard let result = result as? [String] else {
                showMessage(message: error ?? "Can't cast bitcoin-cli result as [String].")
                return
            }
            wallets = result
            showMiningAlert = true
        }
    }
    
    private func mine(wallet: String, numberOfBlocks: String) {
        isLoading = true
        
        let mineEnv = [
            "RPCWALLET" : wallet,
            "PREFIX" : env["PREFIX"]!,
            "DATADIR" : env["DATADIR"]!,
            "NUMBER_OF_BLOCKS": numberOfBlocks
        ]
        
        ScriptUtil.runScript(script: .mineBlocks, env: mineEnv, args: nil) { (output, _, errorMessage) in
            guard let output = output else {
                isLoading = false
                showMessage(message: errorMessage ?? "We did not get a response from your node...")
                return
            }
            isLoading = false
            showMessage(message: output)
        }
    }
    
    /// Checks if a directory contains any file with a specific file extension.
    ///
    /// - Parameters:
    ///   - directoryPath: The path to the directory (e.g., "~/Library/Application Support/Bitcoin/wallets/").
    ///   - fileExtension: The file extension to check for (e.g., "dat") without the dot.
    /// - Returns: `true` if at least one file with the extension exists, `false` otherwise.
    /// - Throws: An error if the directory is invalid or inaccessible.
    func hasFileWithExtension(in directoryPath: String, fileExtension: String) throws -> Bool {
        let fileManager = FileManager.default
        
        // Expand tilde to full path (e.g., "~/Library" -> "/Users/username/Library")
        let expandedPath = NSString(string: directoryPath).expandingTildeInPath
        let directoryURL = URL(fileURLWithPath: expandedPath)
        
        // Check if the directory exists and is accessible
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "DirectoryError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Directory does not exist or is not accessible: \(expandedPath)"
            ])
        }
        
        // Get directory contents
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        
        // Check for any file with the specified extension
        return contents.contains { url in
            if let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                return url.pathExtension.lowercased() == fileExtension.lowercased()
            }
            return false
        }
    }
    
    private func bitcoinConfPath() -> String {
        let dataDir = Defaults.shared.bitcoinCoreDataDir
        return dataDir + "/bitcoin.conf"
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
    
    private func bitcoinConf() -> String? {
        return conf(stringPath: bitcoinConfPath())
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
        
        //updateJMConf(key: "rpc_password", value: newCreds.rpcPassword)
        //updateCLNConfig(rpcpass: newCreds.rpcPassword)
        
        guard let encryptedPass = Crypto.encrypt(passData) else {
            showMessage(message: "Can't encrypt rpcpass data.")
            return
        }
        
        DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: .rpcCreds) { updated in
            guard updated else {
                showMessage(message: "BitcoinRPCCreds update failed")
                return
            }
            showMessage(message: "Password updated, you'll need to restart your node now.")
//            ScriptUtil.runScript(script: .killBitcoind, env: env, args: nil) { (output, rawData, errorMessage) in
//                guard errorMessage == nil else {
//                    showMessage(message: errorMessage!)
//                    return
//                }
//                guard let output = output else {
//                    showMessage(message: "No output when killing Bitcoin Core, you can probably ignore this error. RPC credentials should be updated, ensure Bitcoin Core restarts for the changes to take place.")
//                    return
//                }
//                parseScriptResult(script: .killBitcoind, result: output)
//            }
        }
    }
    
//    func parseScriptResult(script: SCRIPT, result: String) {
//        switch script {
//        case .killBitcoind:
//            if result.contains("Its dead") || result.contains("Does not exist") {
//                showMessage(message: "RPC Authentication refreshed, you need to start your node for the changes to take effect.")
//            }
//        default:
//            break
//        }
//    }
    
//    private func updateCLNConfig(rpcpass: String) {
//        let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
//        guard let conf = conf(stringPath: lightningConfPath) else { return }
//        let arr = conf.split(separator: "\n")
//        for item in arr {
//            if item.hasPrefix("bitcoin-rpcpassword=") {
//                let newConf = conf.replacingOccurrences(of: item, with: "bitcoin-rpcpassword=" + rpcpass)
//                try? newConf.write(to: URL(fileURLWithPath: lightningConfPath), atomically: false, encoding: .utf8)
//            }
//        }
//    }
    
//    private func updateJMConf(key: String, value: String) {
//        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
//        guard let conf = conf(stringPath: jmConfPath) else { return }
//        let arr = conf.split(separator: "\n")
//        for item in arr {
//            if item.hasPrefix("\(key) =") {
//                let newConf = conf.replacingOccurrences(of: item, with: key + " = " + value)
//                try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
//            }
//        }
//    }
    
    private func writeBitcoinConf(newConf: String) -> Bool {
        return ((try? newConf.write(to: URL(fileURLWithPath: bitcoinConfPath()), atomically: false, encoding: .utf8)) != nil)
    }
    
    private func reindex() {
            ScriptUtil.runScript(script: .reindex, env: env, args: nil) { (_, _, errorMessage) in
                guard errorMessage == nil else {
                    if errorMessage != "" {
                        showMessage(message: errorMessage!)
                    }
                    return
                }
                //
                showMessage(message: "Reindex initiated, this can take awhile. Refresh the Bitcoin Core view.")
            }
        
    }
    
    private func debugLogPath() -> String? {
        let chain = Defaults.shared.chain
        var debugLogPath: String?
        switch chain {
        case "main":
            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/debug.log"
        case "test":
            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/testnet3/debug.log"
        case "regtest":
            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/regtest/debug.log"
        case "signet":
            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/signet/debug.log"
        default:
            break
        }
        return debugLogPath
    }
    
    private func openDataDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Defaults.shared.bitcoinCoreDataDir)
    }
    
    private func verify() {
        ScriptUtil.runScript(script: .launchVerifier, env: env, args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
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
}

//#Preview {
//    BtcUtilsView(selectedChain: $)
//}
