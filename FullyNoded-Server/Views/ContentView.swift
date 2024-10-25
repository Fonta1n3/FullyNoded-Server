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
    
    @State private var showError = false
    @State private var message = ""
    @State private var services: [Service] = []
    @State private var bitcoinCoreInstalled = false
    @State private var lightningInstalled = false
    @State private var joinMarketInstalled = false
    @State private var xcodeSelectInstalled = false
    @State private var promptToInstallXcode = false
    @State private var promptToInstallBitcoin = false
    @State private var promptToInstallJoinMarket = false
    @State private var startCheckingForBitcoinInstall = false
    @State private var startCheckingForLightningInstall = false
    @State private var bitcoinInstallSuccess = false
    @State private var timeRemaining = 90
    @State private var promptToInstallBrew = false
    @State private var promptToInstallLightning = false
    @State private var torRunning = false
    @State private var taggedReleases: TaggedReleases? = nil
    @State private var showingBitcoinReleases = false
    @State private var jmTaggedReleases: TaggedReleases = []
    private let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForLightningInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForJMInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForTor = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let bitcoinCore = Service(name: "Bitcoin Core", id: UUID())
    private let coreLightning = Service(name: "Core Lightning", id: UUID())
    private let joinMarket = Service(name: "Join Market", id: UUID())
    private let tor = Service(name: "Tor", id: UUID())
    
    @State private var bitcoinEnvValues: BitcoinEnvValues = .init(dictionary: [
        "binaryName": "bitcoin-26.2-arm64-apple-darwin.tar.gz",
        "version": "26.2",
        "prefix": "bitcoin-26.2",
        "dataDir": "/Users/\(NSUserName())/Library/Application Support/Bitcoin",
        "chain": "signet"
    ])
    
    @State private var env: [String: String] = [:]
    

    var body: some View {
        NavigationView {
            List {
                ForEach(services) { service in
                    NavigationLink {
                        if service.name == "Bitcoin Core" {
                            BitcoinCore()
                        }
                        if service.name == "Core Lightning" {
                            CoreLightning()
                        }
                        if service.name == "Join Market" {
                            JoinMarket()
                        }
                    } label: {
                        HStack() {
                            if service.name == "Bitcoin Core" {
                                if bitcoinCoreInstalled {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.gray)
                                    EmptyView()
                                        .onReceive(timerForBitcoinInstall) { _ in
                                            DataManager.retrieve(entityName: "BitcoinEnv") { bitcoinEnv in
                                                guard let bitcoinEnv = bitcoinEnv else { return }
                                                let envValues = BitcoinEnvValues(dictionary: bitcoinEnv)
                                                let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(envValues.prefix)/bin/bitcoind"
                                                if FileManager.default.fileExists(atPath: tempPath) {
                                                    bitcoinCoreInstalled = true
                                                    self.timerForBitcoinInstall.upstream.connect().cancel()
                                                }
                                            }
                                            
                                        }
                                }
                            }
                            
                            if service.name == "Core Lightning" {
                                if lightningInstalled {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.gray)
                                    EmptyView()
                                        .onReceive(timerForLightningInstall) { _ in
                                            if FileManager.default.fileExists(atPath: "/usr/local/bin/lightningd") {
                                                lightningInstalled = true
                                                self.timerForLightningInstall.upstream.connect().cancel()
                                            }
                                        }
                                }
                            }
                            
                            if service.name == "Join Market" {
                                if joinMarketInstalled {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.gray)
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
                            
                            if service.name == "Tor" {
                                if torRunning {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.gray)
                                }
                                
                                EmptyView()
                                    .onReceive(timerForTor) { _ in
                                        self.torRunning = TorClient.sharedInstance.state == .connected
                                    }
                            }
                            Text(service.name)
                        }
                    }
                }
            }
            Home(
                showBitcoinCoreInstallButton: promptToInstallBitcoin,
                env: env,
                showJoinMarketInstallButton: !joinMarketInstalled,
                jmTaggedReleases: jmTaggedReleases
            )
        }
        .onAppear(perform: {
            getSavedValues()
            
        })
        .alert("Install Core Lightning?", isPresented: $promptToInstallLightning) {
            Button("OK") {
                installLightning()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Install Brew? Core Lightning and Join Market installation relies on Brew.", isPresented: $promptToInstallBrew) {
            Button("OK", role: .cancel) {
                runScript(script: .installHomebrew, env: [:])
            }
        }
        .alert("Bitcoin Install complete.", isPresented: $bitcoinInstallSuccess) {
            Button("OK", role: .cancel) {
                runScript(script: .checkForBitcoin, env: env)
            }
        }
        .alert("A terminal should have launched to install Bitcoin Core, close the terminal window when it says its finished.", isPresented: $startCheckingForBitcoinInstall) {
            Button("OK", role: .cancel) {}
        }
        
        .alert("Install XCode command line tools? FullyNoded-Server relies on Xcode command line tools to function.", isPresented: $promptToInstallXcode) {
            Button("OK", role: .cancel) {
                runScript(script: .installXcode, env: env)
            }
        }
    }
    
    private func installLightning() {
        DataManager.retrieve(entityName: "BitcoinRPCCreds") { bitcoinRPCCreds in
            guard let bitcoinRPCCreds = bitcoinRPCCreds else {
                showMessage(message: "NO Bitcoin RPC Creds, create them?")
                return
            }
            
            guard let encryptedRpcPass = bitcoinRPCCreds["password"] as? Data else {
                showMessage(message: "Unable to get encrypted rpc password.")
                return
            }
            
            guard let decryptedRpcPass = Crypto.decrypt(encryptedRpcPass) else {
                showMessage(message: "Decrypting rpc password failed.")
                return
            }
            
            guard let rpcPass = String(data: decryptedRpcPass, encoding: .utf8) else {
                showMessage(message: "Encoding rpc password data as utf8 failed.")
                return
            }
            
            var lightningEnv: [String: String] = [:]
            lightningEnv["RPC_USER"] = UserDefaults.standard.string(forKey: "rpcuser")
            lightningEnv["RPC_PASSWORD"] = rpcPass
            lightningEnv["DATA_DIR"] = bitcoinEnvValues.dataDir.replacingOccurrences(of: " ", with: "*")
            lightningEnv["PREFIX"] = bitcoinEnvValues.prefix
            var network = "bitcoin"
            if bitcoinEnvValues.chain != "main" {
                 network = bitcoinEnvValues.chain
            }
            lightningEnv["NETWORK"] = network
            
            runScript(script: .launchLightningInstall, env: lightningEnv)
        }
    }
    
    private func getSavedValues() {
        DataManager.retrieve(entityName: "BitcoinEnv") { bitcoinEnv in
            guard let bitcoinEnv = bitcoinEnv else {
                let dict = [
                    "binaryName": "bitcoin-26.2-arm64-apple-darwin.tar.gz",
                    "version": "26.2",
                    "prefix": "bitcoin-26.2",
                    "dataDir": "/Users/\(NSUserName())/Library/Application Support/Bitcoin",
                    "chain": "signet"
                ]
                
                DataManager.saveEntity(entityName: "BitcoinEnv", dict: dict) { saved in
                    guard saved else {
                        showMessage(message: "Unable to save default bitcoin env values.")
                        return
                    }
                    
                    self.env = [
                        "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                        "VERSION": self.bitcoinEnvValues.version,
                        "PREFIX": self.bitcoinEnvValues.prefix,
                        "DATADIR": self.bitcoinEnvValues.dataDir,
                        "CHAIN": self.bitcoinEnvValues.chain
                    ]
                    
                    services = [bitcoinCore, coreLightning, joinMarket, tor]
                    runScript(script: .checkForBitcoin, env: env)
                }
                
                return
            }
            
            
            self.bitcoinEnvValues = .init(dictionary: bitcoinEnv)
            
            self.env = [
                "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                "VERSION": self.bitcoinEnvValues.version,
                "PREFIX": self.bitcoinEnvValues.prefix,
                "DATADIR": self.bitcoinEnvValues.dataDir,
                "CHAIN": self.bitcoinEnvValues.chain
            ]
                        
            services = [bitcoinCore, coreLightning, joinMarket, tor]
            runScript(script: .checkForBitcoin, env: env)
        }
    }
    
    func parseBitcoindVersionResponse(result: String) {
        if result.contains("Bitcoin Core Daemon version") || result.contains("Bitcoin Core version") {
            bitcoinCoreInstalled = true
            runScript(script: .checkForBrew, env: env)
            let tempPath = "/Users/\(NSUserName())/.fullynoded/installBitcoin.sh"
            if FileManager.default.fileExists(atPath: tempPath) {
                try? FileManager.default.removeItem(atPath: tempPath)
            }
            
            if let tagName = UserDefaults.standard.object(forKey: "tagName") as? String {
                let jmWalletDPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName)/scripts/jmwalletd.py"
                guard !FileManager.default.fileExists(atPath: jmWalletDPath)  else {
                    print("join market already installed")
                    joinMarketInstalled = true
                    return
                }
                
                getJmRelease()
            } else {
                getJmRelease()
            }
        } else {
            bitcoinCoreInstalled = false
            promptToInstallBitcoin = true
            lightningInstalled = false
        }
    }
    
    private func getJmRelease() {
        LatestJoinMarketRelease.get { (releases, error) in
            if let releases = releases {
                jmTaggedReleases = releases
                promptToInstallJoinMarket = true
            }
        }
    }
    
    private func runScript(script: SCRIPT, env: [String: String]) {
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
    
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    func parseScriptResult(script: SCRIPT, result: String) {
        #if DEBUG
        print("parse \(script.stringValue)")
        print("result: \(result)")
        #endif
        switch script {
        case .checkForBitcoin:
            parseBitcoindVersionResponse(result: result)

        case .checkXcodeSelect:
            parseXcodeSelectResult(result: result)
            
        case .checkForBrew:
            if result != "" {
                runScript(script: .lightningInstalled, env: env)
            } else {
                promptToInstallBrew = true
            }
            
        case .lightningInstalled:
            if result.hasPrefix("Installed") {
                runScript(script: .lightingRunning, env: env)
                lightningInstalled = true  
            } else {
                lightningInstalled = false
                promptToInstallLightning = true
            }
            
        default:
            break
        }
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

#Preview {
    ContentView()
}
