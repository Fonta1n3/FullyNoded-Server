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
    @State private var bitcoinCoreRunning = false
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
    @State private var isLightningRunning = false
    let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    let timerForLightningInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    @State private var bitcoinCore = Service(name: "Bitcoin Core", id: UUID(), running: false)
    private let coreLightning = Service(name: "Core Lightning", id: UUID(), running: false)
    private let joinMarket = Service(name: "Join Market", id: UUID(), running: false)
    private var env = [String:String]()
    private var envValues: EnvValues
    
    private struct EnvValues {
        let binaryName: String
        let version: String
        let prefix: String
        let dataDir: String
        let chain: String
    }
    
    init() {
        self.envValues = EnvValues(
            binaryName: "bitcoin-26.2-arm64-apple-darwin.tar.gz",
            version: "26.2",
            prefix: "bitcoin-26.2",
            dataDir: "/Users/fontaine/Library/Application Support/Bitcoin",
            chain: "signet"
        )
        
        self.env = [
            "BINARY_NAME": envValues.binaryName,
            "VERSION": envValues.version,
            "PREFIX": envValues.prefix,
            "DATADIR": envValues.dataDir,
            "CHAIN": envValues.chain
        ]
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(services) { service in
                    NavigationLink {
                        if service.name == "Bitcoin Core" {
                            BitcoinCore(bitcoinCoreService: service, env: env, running: bitcoinCoreRunning)
                        }
                    } label: {
                        HStack() {
                            if service.name == "Bitcoin Core" {
                                if bitcoinCoreRunning {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            if service.name == "Core Lightning" {
                                if lightningInstalled {
                                    if isLightningRunning {
                                        Image(systemName: "circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                        
                                } else {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.red)
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
                                            let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(envValues.prefix)/bin"
                                            if FileManager.default.fileExists(atPath: tempPath) {
                                                showMessage(message: "Bitcoin Core install completed ✓")
                                                //bitcoinInstallSuccess = true
//                                                startCheckingForInstall = false
                                                runScript(script: .checkForBitcoin)
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
            services = [bitcoinCore, coreLightning, joinMarket]
            runScript(script: .checkForBitcoin)
        })
        .alert("Install Core Lightning?", isPresented: $promptToInstallLightning) {
            Button("OK") {
                runScript(script: .launchLightningInstall)
                // start timer
            }
            Button("Cancel", role: .cancel) {}
            
        }
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Install Brew? Core Lightning installation relies on Brew.", isPresented: $promptToInstallBrew) {
            Button("OK", role: .cancel) {}
        }
        .alert("Bitcoin Install complete.", isPresented: $bitcoinInstallSuccess) {
            Button("OK", role: .cancel) {
                runScript(script: .checkForBitcoin)
            }
        }
        .alert("A terminal should have launched to install Bitcoin Core, close the terminal window when it says its finished.", isPresented: $startCheckingForBitcoinInstall) {
            Button("OK", role: .cancel) {}
        }
        .alert("Install Bitcoin Core?", isPresented: $promptToInstallBitcoin) {
            Button("OK", role: .cancel) {
                // check for xcode select first.
                runScript(script: .checkXcodeSelect)
            }
        }
        .alert("Install XCode command line tools? FullyNoded-Server relies on XCode command line tools to function.", isPresented: $promptToInstallXcode) {
            Button("OK", role: .cancel) {
                runScript(script: .installXcode)
            }
        }
    }
    
    func parseBitcoindVersionResponse(result: String) {
        if result.contains("Bitcoin Core Daemon version") || result.contains("Bitcoin Core version") {
            bitcoinCoreInstalled = true
            runScript(script: .isBitcoindRunning)
            let tempPath = "/Users/\(NSUserName())/.fullynoded/installBitcoin.sh"
            if FileManager.default.fileExists(atPath: tempPath) {
                try? FileManager.default.removeItem(atPath: tempPath)
            }
            
        } else {
            bitcoinCoreInstalled = false
            promptToInstallBitcoin = true
        }
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
            
        case .isBitcoindRunning:
            if result.contains("Running") {
                bitcoinCoreRunning = true
            } else if result.contains("Stopped") {
                bitcoinCoreRunning = false
            }
            runScript(script: .checkForBrew)
            // Check lightning here
            // Check JM after
            //isLightningInstalled
        case .checkForBrew:
            if result != "" {
                // brew is installed
                //promptToInstallLightning = true
                runScript(script: .lightningInstalled)
            } else {
                promptToInstallBrew = true
            }
            
        case .lightningInstalled:
            if result.contains("core-lightning") {
                print("lightning already installed?")
                // check if its running
                runScript(script: .lightingRunning)
            } else {
                promptToInstallLightning = true
            }
            
        case .lightingRunning:
            parseIsLightningRunningResponse(result: result)
            
            
            
        default:
            break
        }
    }
    
    private func parseIsLightningRunningResponse(result: String) {
        if result.contains("Running") {
            isLightningRunning = true
        } else {
            isLightningRunning = false
        }
    }
    
    private func convertStringToDictionary(json: String) -> [String: AnyObject]? {
            if let data = json.data(using: .utf8) {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [.mutableLeaves, .allowFragments]) as? [String: AnyObject]
                    return json
                } catch {
                    return nil
                }
            }
            return nil
        }
    
    private func parseXcodeSelectResult(result: String) {
        if result.contains("XCode select not installed") {
            promptToInstallXcode = true
        } else {
            promptToInstallXcode = false
            
            LatestBtcCoreRelease.get { (dict, error) in                
                if error != nil {
                    
                    print("error: \(error!)")
                } else {
                    print("dict: \(dict!)")
                    InstallBitcoinCore.checkExistingConf()
                    // Set timer to see if install was successful
                    startCheckingForBitcoinInstall = true
                }
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
