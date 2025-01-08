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
    
    @State private var promptToShowPythonGuide = false
    @State private var isInitialLoad = true
    @State private var isInstallingLightning = false
    @State private var torProgress = 0.0
    @State private var showError = false
    @State private var message = ""
    @State private var services: [Service] = []
    @State private var bitcoinCoreInstalled = false
    @State private var lightningInstalled = false
    @State private var joinMarketInstalled = false
    @State private var promptToInstallXcode = false
    @State private var promptToInstallBitcoin = false
    @State private var startCheckingForBitcoinInstall = false
    @State private var startCheckingForLightningInstall = false
    @State private var bitcoinInstallSuccess = false
    @State private var timeRemaining = 90
    @State private var promptToInstallBrew = false
    @State private var promptToInstallLightning = false
    @State private var torRunning = false
    @State private var showingBitcoinReleases = false
    @State private var env: [String: String] = [:]
    @State private var jmTaggedReleases: TaggedReleases = []
    @State private var taggedReleases: TaggedReleases? = nil
    @State private var bitcoinEnvValues: BitcoinEnvValues = .init(dictionary: [
        "binaryName": "bitcoin-28.1-arm64-apple-darwin.tar.gz",
        "version": "28.1",
        "prefix": "bitcoin-28.1",
        "dataDir": Defaults.shared.dataDir,
        "chain": Defaults.shared.chain
    ])
    
    private let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForLightningInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForJMInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let timerForTor = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let bitcoinCore = Service(name: "Bitcoin Core", id: UUID())
    //private let coreLightning = Service(name: "Core Lightning", id: UUID())
    private let joinMarket = Service(name: "Join Market", id: UUID())
    private let tor = Service(name: "Tor", id: UUID())
    private let help = Service(name: "Help", id: UUID())
    

    var body: some View {
            NavigationView {
                List {
                    ForEach(services) { service in
                        NavigationLink {
                            if service.name == "Bitcoin Core" {
                                if bitcoinCoreInstalled {
                                    BitcoinCore()
                                } else {
                                    Home(
                                        showBitcoinCoreInstallButton: true,
                                        env: env,
                                        showJoinMarketInstallButton: false,
                                        jmTaggedReleases: []
                                    )
                                }
                            } else if service.name == "Core Lightning" {
                                if isInstallingLightning {
                                    HStack() {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                        Text("Installing and configuring Core Lightning. (wait for the terminal script to complete)")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding([.leading, .top])
                                    
                                } else if lightningInstalled {
                                    CoreLightning()
                                } else {
                                    FNIcon()
                                    Spacer()
                                    if bitcoinCoreInstalled {
                                        Button("Install Core Lightning") {
                                            installLightning()
                                        }
                                        Spacer()
                                    } else {
                                        Text("First install Bitcoin Core.")
                                    }
                                }
                                
                            } else if service.name == "Join Market" {
                                if joinMarketInstalled {
                                    JoinMarket()
                                } else {
                                    if !bitcoinCoreInstalled {
                                        Text("First install Bitcoin Core.")
                                    }
                                    Home(
                                        showBitcoinCoreInstallButton: false,
                                        env: env,
                                        showJoinMarketInstallButton: true,
                                        jmTaggedReleases: jmTaggedReleases
                                    )
                                }
                            } else if service.name == "Tor" {
                                FNIcon()
                                HStack() {
                                    if torProgress < 100.0 {
                                        ProgressView("Tor v0.4.8.12 bootstrapping \(Int(torProgress))% complete…", value: torProgress, total: 100)
                                            .padding([.leading, .trailing])
                                            .frame(alignment: .topLeading)
                                    } else {
                                        if torRunning {
                                            Image(systemName: "circle.fill")
                                                .foregroundStyle(.green)
                                                .padding([.leading])
                                            Text("Tor v0.4.8.12 running")
                                        } else {
                                            Image(systemName: "circle.fill")
                                                .foregroundStyle(.orange)
                                                .padding([.leading])
                                            Text("Tor v0.4.8.12 stopped")
                                        }
                                    }
                                    Toggle("", isOn: $torRunning)
                                        .toggleStyle(SwitchToggleStyle())
                                        .onChange(of: torRunning) {
                                            if !torRunning {
                                                TorClient.sharedInstance.resign()
                                            } else if !isInitialLoad && TorClient.sharedInstance.state != .connected {
                                                TorClient.sharedInstance.start(delegate: nil)
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                            } else if service.name == "Help" {
                                Help()
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
                                                DataManager.retrieve(entityName: .bitcoinEnv) { bitcoinEnv in
                                                    guard let bitcoinEnv = bitcoinEnv else { return }
                                                    let envValues = BitcoinEnvValues(dictionary: bitcoinEnv)
                                                    let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(envValues.prefix)/bin/bitcoind"
                                                    if FileManager.default.fileExists(atPath: tempPath) {
                                                        bitcoinCoreInstalled = true
                                                        self.timerForBitcoinInstall.upstream.connect().cancel()
                                                        getJmRelease()
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
                                                if FileManager.default.fileExists(atPath: "/opt/homebrew/Cellar/core-lightning/24.11/bin/lightningd") {
                                                    lightningInstalled = true
                                                    isInstallingLightning = false
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
                                    if torProgress < 100.0 {
                                        ProgressView()
#if os(macOS)
                                            .scaleEffect(0.5)
#endif
                                    } else {
                                        if torRunning {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "xmark")
                                                .foregroundStyle(.gray)
                                        }
                                    }
                                    
                                    EmptyView()
                                        .onReceive(timerForTor) { _ in
                                            self.torRunning = TorClient.sharedInstance.state == .connected
                                        }
                                }
                                
                                if service.name == "Help" {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                    Text(service.name)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(service.name)
                                }
                            }
                            
                        }
                    }
                }.padding()
                Text("Select a service.")
                    .foregroundStyle(.secondary)
            }
        
        .onAppear(perform: {
            if isInitialLoad {
                bootTor()
            }
            checkForXcode()
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
        .alert("Python 3.10-3.12 is a Join Market dependency. Would you like to see a guide on how to easily install it?", isPresented: $promptToShowPythonGuide) {
                    Link("Open Python install guide", destination: URL(string: "https://www.codingforentrepreneurs.com/guides/install-python-on-macos")!)
        }
        .alert("Install Brew? Core Lightning and Join Market installation relies on Brew.", isPresented: $promptToInstallBrew) {
            Button("OK", role: .cancel) {
                ScriptUtil.runScript(script: .installHomebrew, env: nil, args: nil) { (_, _, _) in }
            }
        }
        .alert("Install Xcode Command Line Tools? This is required for Fully Noded - Server to function.", isPresented: $promptToInstallXcode, actions: {
            Button("OK", role: .cancel) {
                ScriptUtil.runScript(script: .installXcode, env: nil, args: nil) { (_, _, _) in }
            }
        })
        .alert("Bitcoin Install complete.", isPresented: $bitcoinInstallSuccess) {
            Button("OK", role: .cancel) {
                checkForBitcoin()
            }
        }
        .alert("A terminal should have launched to install Bitcoin Core, close the terminal window when it says its finished.", isPresented: $startCheckingForBitcoinInstall) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func checkForXcode() {
        ScriptUtil.runScript(script: .checkXcodeSelect, env: nil, args: nil) { (output, data, errorMess) in
            guard let output = output else {
                showMessage(message: errorMess ?? "Unknown error checking for xcode select.")
                return
            }
            if output.contains("XCode select installed") {
                promptToInstallXcode = false
                checkForBrew()
            } else if output.contains("XCode select not installed") {
                promptToInstallXcode = true
            }
        }
    }
    
    private func bootTor() {
        if TorClient.sharedInstance.state == .connected {
            torProgress = 100.0
        } else {
            TorClient.sharedInstance.start(delegate: nil)
        }
        TorClient.sharedInstance.showProgress = { progress in
            torProgress = Double(progress)
        }
        isInitialLoad = false
    }
    
    private func checkForBrew() {
        ScriptUtil.runScript(script: .checkForBrew, env: nil, args: nil) { (output, data, errorMess) in
            guard let output = output, output != "" else {
                promptToInstallBrew = true
                return
            }
            getSavedValues()
        }
    }
    
    private func installLightning() {
        isInstallingLightning = true
        DataManager.retrieve(entityName: .rpcCreds) { bitcoinRPCCreds in
            guard let bitcoinRPCCreds = bitcoinRPCCreds else {
                isInstallingLightning = false
                showMessage(message: "NO Bitcoin RPC Creds, create them?")
                return
            }
            
            guard let encryptedRpcPass = bitcoinRPCCreds["password"] as? Data else {
                isInstallingLightning = false
                showMessage(message: "Unable to get encrypted rpc password.")
                return
            }
            
            guard let decryptedRpcPass = Crypto.decrypt(encryptedRpcPass) else {
                isInstallingLightning = false
                showMessage(message: "Decrypting rpc password failed.")
                return
            }
            
            guard let rpcPass = String(data: decryptedRpcPass, encoding: .utf8) else {
                isInstallingLightning = false
                showMessage(message: "Encoding rpc password data as utf8 failed.")
                return
            }
            
            var lightningEnv: [String: String] = [:]
            lightningEnv["RPC_USER"] = UserDefaults.standard.string(forKey: "rpcuser")
            lightningEnv["RPC_PASSWORD"] = rpcPass
            lightningEnv["DATA_DIR"] = Defaults.shared.dataDir.replacingOccurrences(of: " ", with: "*")
            lightningEnv["PREFIX"] = bitcoinEnvValues.prefix
            var network = "bitcoin"
            if Defaults.shared.chain != "main" {
                 network = Defaults.shared.chain
            }
            lightningEnv["NETWORK"] = network
            
            ScriptUtil.runScript(script: .launchLightningInstall, env: lightningEnv, args: nil) { (output, rawData, errorMessage) in
                guard errorMessage == nil else {
                    if errorMessage != "" {
                        showMessage(message: errorMessage!)
                    }
                    return
                }
                return
            }
        }
    }
    
    private func getSavedValues() {
        DataManager.retrieve(entityName: .bitcoinEnv) { bitcoinEnv in
            guard let bitcoinEnv = bitcoinEnv else {
                let dict = [
                    "binaryName": "bitcoin-28.1-arm64-apple-darwin.tar.gz",
                    "version": "28.1",
                    "prefix": "bitcoin-28.1",
                    "dataDir": Defaults.shared.dataDir,
                    "chain": Defaults.shared.chain
                ]
                
                DataManager.saveEntity(entityName: .bitcoinEnv, dict: dict) { saved in
                    guard saved else {
                        showMessage(message: "Unable to save default bitcoin env values.")
                        return
                    }
                    
                    self.env = [
                        "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                        "VERSION": self.bitcoinEnvValues.version,
                        "PREFIX": self.bitcoinEnvValues.prefix,
                        "DATADIR": Defaults.shared.dataDir,
                        "CHAIN": self.bitcoinEnvValues.chain
                    ]
                    
                    //services = [bitcoinCore, coreLightning, joinMarket, tor, help]
                    services = [bitcoinCore, joinMarket, tor, help]
                    checkForBitcoin()
                }
                
                return
            }
            
            
            self.bitcoinEnvValues = .init(dictionary: bitcoinEnv)
            
            self.env = [
                "BINARY_NAME": self.bitcoinEnvValues.binaryName,
                "VERSION": self.bitcoinEnvValues.version,
                "PREFIX": self.bitcoinEnvValues.prefix,
                "DATADIR": Defaults.shared.dataDir,
                "CHAIN": self.bitcoinEnvValues.chain
            ]
                        
            //services = [bitcoinCore, coreLightning, joinMarket, tor, help]
            services = [bitcoinCore, joinMarket, tor, help]
            checkForBitcoin()
        }
    }
    
    private func checkForBitcoin() {
        ScriptUtil.runScript(script: .checkForBitcoin, env: env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else if let output = output {
                    parseBitcoindVersionResponse(result: output)
                }
                return
            }
            guard let output = output else { return }
            parseBitcoindVersionResponse(result: output)
        }
    }
    
    func parseBitcoindVersionResponse(result: String) {
        if result.contains("Bitcoin Core Daemon version") || result.contains("Bitcoin Core version") {
            bitcoinCoreInstalled = true
            let tempPath = "/Users/\(NSUserName())/.fullynoded/installBitcoin.sh"
            if FileManager.default.fileExists(atPath: tempPath) {
                try? FileManager.default.removeItem(atPath: tempPath)
            }
            
            if let tagName = UserDefaults.standard.object(forKey: "tagName") as? String {
                let jmWalletDPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName)/scripts/jmwalletd.py"
                guard !FileManager.default.fileExists(atPath: jmWalletDPath)  else {
                    joinMarketInstalled = true
                    return
                }
                
                guard FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.10"), FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.11"),
                      FileManager.default.fileExists(atPath: "/Library/Frameworks/Python.framework/Versions/3.12")else {
                    promptToShowPythonGuide = true
                    return
                }
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
            }
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
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
