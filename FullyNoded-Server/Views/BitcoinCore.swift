//
//  BitcoinCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

struct BitcoinCore: View {
    
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var logOutput = ""
    var chains = ["Mainnet", "Testnet", "Signet", "Regtest"]
    @State private var selectedChain = "Signet"
        
    
    let env: [String: String]
    
    init(env: [String : String]) {
        self.env = env
    }
    
    
    var body: some View {
        HStack() {
            if isAnimating {
                ProgressView()
                    .scaleEffect(0.5)
            }
            if isRunning {
                if isAnimating {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                }
               
            } else {
                if isAnimating {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.red)
                }
            }
            Toggle("Bitcoin Core", isOn: $isRunning)
                .toggleStyle(.switch)
                .onChange(of: isRunning) {
                    if !isRunning {
                        stopBitcoinCore()
                    } else {
                        startBitcoinCore()
                    }
                }
            
            
            Picker("", selection: $selectedChain) {
                ForEach(chains, id: \.self) {
                    Text($0)
                }
            }
            
            Button {
                isBitcoinCoreRunning()
            } label: {
                Image(systemName: "arrow.clockwise")

            }
            .padding(.all)
        }
        .padding([.top, .leading, .trailing])
        
        HStack() {
            Button {
                runScript(script: .launchVerifier)
            } label: {
                Text("Verify")
            }
            
            Button {
                print("update")
            } label: {
                Text("Update")
            }
            
            Button {
                let d = Defaults.shared
                let path = d.dataDir
                let env = ["FILE":"\(path)/bitcoin.conf"]
                openConf(script: .openFile, env: env, args: []) { _ in }
            } label: {
                Text("bitcoin.conf")
            }
        }
        .padding([.leading, .trailing])
        
        
        
        Spacer()
        HStack() {
            Label(logOutput, systemImage: "info.circle")
                .padding(.all)
        }
        .onAppear(perform: {
            isBitcoinCoreRunning()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func startBitcoinCore() {
        isAnimating = true
        runScript(script: .startBitcoin)
    }
    
    private func startBitcoinParse(result: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.runScript(script: .didBitcoindStart)
        }
    }
    
    private func parseDidBitcoinStart(result: String) {
        if !result.contains("Stopped") {
            isBitcoinOn()
        }
    }
    
    func isBitcoinOn() {
        isAnimating = true
        runScript(script: .isBitcoindRunning)
    }
    
    private func stopBitcoinCore() {
        isAnimating = true
        BitcoinRPC.shared.command(method: "stop") { (result, error) in
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
            print("bitcoin core stopped")
            isRunning = false
            
            
//            DispatchQueue.main.async() {
//                self.shutDownTimer?.invalidate()
//                self.shutDownTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.queryShutDownStatus), userInfo: nil, repeats: true)
//            }
        } else {
            isRunning = true
            showMessage(message: "Error turning off mainnet")
        }
    }
    
//    @objc func queryShutDownStatus() {
//        showBitcoinLog()
//        runScript(script: .hasBitcoinShutdownCompleted)
//    }
    
    private func showBitcoinLog() {
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "signet"
        var path:URL?
        
        switch chain {
        case "main":
            path = URL(fileURLWithPath: "/Users/fontaine/Library/Application Support/Bitcoin/debug.log")
        case "test":
            path = URL(fileURLWithPath: "/Users/fontaine/Library/Application Support/Bitcoin/testnet3/debug.log")
        case "regtest":
            path = URL(fileURLWithPath: "/Users/fontaine/Library/Application Support/Bitcoin/regtest/debug.log")
        case "signet":
            path = URL(fileURLWithPath: "/Users/fontaine/Library/Application Support/Bitcoin/signet/debug.log")
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
                //self.bitcoinCoreLogOutlet.stringValue = "\(logItems[logItems.count - 2])"
                let lastLogItem = "\(logItems[logItems.count - 2])"
                logOutput = lastLogItem
                
                if lastLogItem.contains("Shutdown: done") {
//                    self.hideSpinner()
//                    self.bitcoinIsOff()
                }
                
                if lastLogItem.contains("ThreadRPCServer incorrect password") {
                    showMessage(message: lastLogItem)
                }
            }
        }
    }
    
    private func isBitcoinCoreRunning() {
        isAnimating = true
        runScript(script: .isBitcoindRunning)
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
                //#if DEBUG
                print("output: \(output)")
                //#endif
                result += output
            }
            
            if let errorOutput = String(data: errData, encoding: .utf8) {
                //#if DEBUG
                print("error: \(errorOutput)")
                //#endif
                result += errorOutput
                
                if errorOutput != "" {
                    //simpleAlert(message: "There was an issue, please let us know about it via Github issues.", info: errorOutput, buttonLabel: "OK")
                    showMessage(message: errorOutput)
                }
            }
            
            parseScriptResult(script: script, result: result)
        }
    }
    
    func parseScriptResult(script: SCRIPT, result: String) {
        print("parse \(script.stringValue)")
        switch script {
        case .startBitcoin:
            showBitcoinLog()
            startBitcoinParse(result: result)
            
//        case .checkForBitcoin:
//            parseBitcoindVersionResponse(result: result)
//            
//        case .checkXcodeSelect:
//            parseXcodeSelectResult(result: result)
//            
//        case .hasBitcoinShutdownCompleted:
//            parseHasBitcoinShutdownCompleted(result: result)
            
        case .isBitcoindRunning:
            isAnimating = false
            if result.contains("Running") {
                isRunning = true
            } else if result.contains("Stopped") {
                isRunning = false
            }
            showBitcoinLog()
        case .didBitcoindStart:
            parseDidBitcoinStart(result: result)
            
        default:
            break
        }
    }
    
    private func openConf(script: SCRIPT, env: [String:String], args: [String], completion: @escaping ((Bool)) -> Void) {
        #if DEBUG
        print("script: \(script.stringValue)")
        #endif
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
            #if DEBUG
            print("result: \(output)")
            #endif
            result += output
            completion(true)
        } else {
            completion(false)
        }
    }
}
