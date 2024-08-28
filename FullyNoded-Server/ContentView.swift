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
                            Text(service.name)
                        }
                    }
                }
            }
            //Text("Select a service")
            Home()
        }
        .onAppear(perform: {
            services = [bitcoinCore, coreLightning, joinMarket]
            runScript(script: .isBitcoindRunning)
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
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
//        case .startBitcoin:
//            showBitcoinLog()
//            startBitcoinParse(result: result)
            
//        case .checkForBitcoin:
//            parseBitcoindVersionResponse(result: result)
//
//        case .checkXcodeSelect:
//            parseXcodeSelectResult(result: result)
//
//        case .hasBitcoinShutdownCompleted:
//            parseHasBitcoinShutdownCompleted(result: result)
            
        case .isBitcoindRunning:
            print("result: \(result)")
            if result.contains("Running") {
                bitcoinCoreRunning = true
            } else if result.contains("Stopped") {
                bitcoinCoreRunning = false
            }
            // Check lightning here
            // Check JM after
            
//        case .didBitcoindStart:
//            parseDidBitcoinStart(result: result)
            
        default:
            break
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
