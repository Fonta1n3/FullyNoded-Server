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
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
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
            .padding([.leading, .trailing])
        }
        .padding([.leading, .trailing, .bottom])
        
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
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Spacer()
        
        HStack() {
            Label(logOutput, systemImage: "info.circle")
                .padding(.all)
        }
        .onAppear(perform: {
            selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
            // get the bitcoin env values
            // need to ensure changing networks here updates the env values too.
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
            
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
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
        self.env["chain"] = chain
        DataManager.update(keyToUpdate: "chain", newValue: chain, entity: "BitcoinEnv") { updated in
            guard updated else {
                showMessage(message: "There was an issue updating your network...")
                return
            }
            isBitcoinCoreRunning()
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
            isBitcoinCoreRunning()
        }
    }
    
//    func isBitcoinOn() {
//        isAnimating = true
//        //runScript(script: .isBitcoindRunning)
//        BitcoinRPC.shared.command(method: "getblockchaininfo") { (result, error) in
//            if error == nil {
//                
//            }
//        }
//    }
    
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
        //runScript(script: .isBitcoindRunning)
        BitcoinRPC.shared.command(method: "getblockchaininfo") { (result, error) in
            isAnimating = false
            if error == nil {
                isRunning = true
            } else {
                isRunning = false
                showMessage(message: error!)
            }
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
            
//        case .isBitcoindRunning:
//            isAnimating = false
//            if result.contains("Running") {
//                isRunning = true
//            } else if result.contains("Stopped") {
//                isRunning = false
//            }
//            showBitcoinLog()
            
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
