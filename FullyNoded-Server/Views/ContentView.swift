//
//  ContentView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

public struct Service: Identifiable {
    let name: String
    var running: Bool
    public let id: UUID
    
    init(name: String, id: UUID, running: Bool) {
        self.name = name
        self.id = id
        self.running = running
    }
}

struct ContentView: View {
    
    @State private var showError = false
    @State private var message = ""
    @State private var services: [Service] = []
    //@State private var bitcoinCoreRunning = false
    @State private var bitcoinCoreInstalled = false
    @State private var lightningInstalled = false
    @State private var xcodeSelectInstalled = false
    @State private var promptToInstallXcode = false
    @State private var promptToInstallBitcoin = false
    @State private var startCheckingForBitcoinInstall = false
    @State private var startCheckingForLightningInstall = false
    @State private var bitcoinInstallSuccess = false
    @State private var timeRemaining = 90
    @State private var promptToInstallBrew = false
    @State private var promptToInstallLightning = false
    let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    let timerForLightningInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    @State private var bitcoinCore = Service(name: "Bitcoin Core", id: UUID(), running: false)
    private let coreLightning = Service(name: "Core Lightning", id: UUID(), running: false)
    private let joinMarket = Service(name: "Join Market", id: UUID(), running: false)
    
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
                            BitcoinCore(env: env)
                        }
                        if service.name == "Core Lightning" {
                            CoreLightning()
                        }
                    } label: {
                        HStack() {
                            if service.name == "Bitcoin Core" {
                                if bitcoinCoreInstalled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.gray)
                                }
                            }
                            
                            if service.name == "Core Lightning" {
                                if lightningInstalled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.gray)
                                }
                            }
                            
                            Text(service.name)
                            
                            if service.name == "Join Market" {
                                if startCheckingForBitcoinInstall {
                                    EmptyView()
                                    .onReceive(timerForBitcoinInstall) { _ in
                                        // if input exceeds 90 seconds then kill the timer...
                                        if timeRemaining > 0 {
                                            timeRemaining -= 1
                                            let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(bitcoinEnvValues.prefix)/bin"
                                            if FileManager.default.fileExists(atPath: tempPath) {
                                                showMessage(message: "Bitcoin Core install completed ✓")
                                                //bitcoinInstallSuccess = true
//                                                startCheckingForInstall = false
                                                runScript(script: .checkForBitcoin, env: env)
                                                timeRemaining = 90
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Home()
            

            
           
        }
        .onAppear(perform: {
            getSavedValues()
            
        })
        .alert("Install Core Lightning?", isPresented: $promptToInstallLightning) {
            Button("OK") {
                installLightning()
                // start timer
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Install Brew? Core Lightning installation relies on Brew.", isPresented: $promptToInstallBrew) {
            Button("OK", role: .cancel) {
                //runScript...
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
        .alert("Install Bitcoin Core?", isPresented: $promptToInstallBitcoin) {
            Button("OK", role: .cancel) {
                // check for xcode select first.
                runScript(script: .checkXcodeSelect, env: env)
            }
        }
        .alert("Install XCode command line tools? FullyNoded-Server relies on XCode command line tools to function.", isPresented: $promptToInstallXcode) {
            Button("OK", role: .cancel) {
                runScript(script: .installXcode, env: env)
            }
        }
    }
    
    private func installLightning() {
        DataManager.retrieve(entityName: "BitcoinRPCCreds") { bitcoinRPCCreds in
            guard let bitcoinRPCCreds = bitcoinRPCCreds else {
                // Create them..
                
                return
            }
            
            guard let encryptedRpcPass = bitcoinRPCCreds["password"] as? Data else { return }
            
            guard let decryptedRpcPass = Crypto.decrypt(encryptedRpcPass) else { return }
            
            guard let rpcPass = String(data: decryptedRpcPass, encoding: .utf8) else { return }
            
            var lightningEnv: [String: String] = [:]
            lightningEnv["RPC_USER"] = UserDefaults.standard.string(forKey: "rpcuser")
            lightningEnv["RPC_PASSWORD"] = rpcPass
            lightningEnv["DATA_DIR"] = bitcoinEnvValues.dataDir.replacingOccurrences(of: " ", with: "*")
            lightningEnv["PREFIX"] = bitcoinEnvValues.prefix
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
                    
                    services = [bitcoinCore, coreLightning/*, joinMarket*/]
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
            
            services = [bitcoinCore, coreLightning/*, joinMarket*/]
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
            
        } else {
            bitcoinCoreInstalled = false
            promptToInstallBitcoin = true
            lightningInstalled = false
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
                    //simpleAlert(message: "There was an issue, please let us know about it via Github issues.", info: errorOutput, buttonLabel: "OK")
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
        print("parse \(script.stringValue)")
        switch script {
        case .checkForBitcoin:
            parseBitcoindVersionResponse(result: result)

        case .checkXcodeSelect:
            parseXcodeSelectResult(result: result)
            
        case .checkForBrew:
            if result != "" {
                // brew is installed
                //promptToInstallLightning = true
                runScript(script: .lightningInstalled, env: env)
            } else {
                promptToInstallBrew = true
            }
            
        case .lightningInstalled:
            if result.contains("core-lightning") {
                print("lightning already installed?")
                // check if its running
                runScript(script: .lightingRunning, env: env)
                lightningInstalled = true
            } else {
                lightningInstalled = false
                promptToInstallLightning = true
            }
            
//        case .lightingRunning:
//            parseIsLightningRunningResponse(result: result)
            
            
        default:
            break
        }
    }
    
//    private func parseIsLightningRunningResponse(result: String) {
//        if result.contains("Running") {
//            isLightningRunning = true
//        } else {
//            isLightningRunning = false
//        }
//    }
    
    
    
    private func parseXcodeSelectResult(result: String) {
        if result.contains("XCode select not installed") {
            promptToInstallXcode = true
        } else {
            promptToInstallXcode = false
            
            LatestBtcCoreRelease.get { (dict, error) in
                guard let dict = dict else {
                    showMessage(message: error ?? "Unknown issue downloading bitcoin core release.")
                    return
                }
                print("dict: \(dict)")
                // save to core data here...
                InstallBitcoinCore.checkExistingConf()
                // Set timer to see if install was successful
                startCheckingForBitcoinInstall = true
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
