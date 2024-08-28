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
        
    let bitcoinCoreService: Service
    let env: [String: String]
    var running: Bool
    
    init(showError: Bool = false, message: String = "", isRunning: Bool = false, bitcoinCoreService: Service, env: [String : String], running: Bool) {
        self.showError = showError
        self.message = message
        self.isRunning = isRunning
        self.bitcoinCoreService = bitcoinCoreService
        self.env = env
        self.running = running
        self.isRunning = running
    }
    
    
    var body: some View {
        HStack() {
            if isRunning {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.red)
            }
            
            Toggle(bitcoinCoreService.name, isOn: $isRunning)
                .toggleStyle(.switch)
        }
        
        
            .onAppear(perform: {
                isBitcoinCoreInstalled()
            })
    }
    
    private func isBitcoinCoreInstalled() {
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
                isRunning = true
            } else if result.contains("Stopped") {
                isRunning = false
            }
//        case .didBitcoindStart:
//            parseDidBitcoinStart(result: result)
            
        default:
            break
        }
    }
}
