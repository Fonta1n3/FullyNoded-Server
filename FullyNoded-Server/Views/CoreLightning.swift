//
//  CoreLightning.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/11/24.
//

import SwiftUI

struct CoreLightning: View {
    
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var logOutput = ""
    @State private var qrImage: NSImage? = nil
    @State private var nodeId = ""
    @State private var publicUrl = ""

    
    var body: some View {
        
        HStack() {
            Image(systemName: "server.rack")
                .padding(.leading)
            
            Text("Core Lightning Server")
            Spacer()
            Button {
                isLightningOn()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .padding(.trailing)
        }
        .padding([.top])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack() {            
            if isAnimating {
                ProgressView()
                    .scaleEffect(0.5)
            }
            if isRunning {
                if isAnimating {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                        .padding(.leading)
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .padding(.leading)
                }
                Text("Running")
            } else {
                if isAnimating {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                        .padding(.leading)
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.red)
                        .padding(.leading)
                }
                Text("Stopped")
            }
            
            if !isRunning {
                Button {
                    startLightning()
                } label: {
                    Text("Start")
                }
            } else {
                Button {
                    stopLightning()
                } label: {
                    Text("Stop")
                }
            }
            
        }
        .padding([.leading])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Utilities", systemImage: "wrench.and.screwdriver")
            .padding([.leading, .top])
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack() {
            Button {
                let env = ["FILE":"/Users/\(NSUserName())/.lightning/config"]
                openConf(script: .openFile, env: env, args: []) { _ in }
            } label: {
                Text("Config")
            }
            .padding(.leading)
            
            Button {
                let env = ["FILE":"/Users/\(NSUserName())/.lightning/lightning.log"]
                openConf(script: .openFile, env: env, args: []) { _ in }
            } label: {
                Text("Log")
            }
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Quick Connect", systemImage: "qrcode")
            .padding([.leading, .top])
            .frame(maxWidth: .infinity, alignment: .leading)
        
        Button("Connect Plasma", systemImage: "qrcode") {
            showQr()
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        if let qrImage = qrImage {
            
            Image(nsImage: qrImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        self.qrImage = nil
                    }
                }
        }
        Spacer()
        HStack() {
            Label(logOutput, systemImage: "info.circle")
                .padding(.all)
        }
        .onAppear(perform: {
            isLightningOn()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func showQr() {
        getPublicUrl()
    }
    
    private func startLightning() {
        isAnimating = true
        runScript(script: .startLightning)
    }
    
    private func isLightningOn() {
        isAnimating = true
        runScript(script: .lightingRunning)
    }
    
    private func stopLightning() {
        isAnimating = true
        runScript(script: .stopLightning)
    }
    
    private func stopLightningParse(result: String) {
        isAnimating = false
        if result.contains("Shutdown complete") {
            isRunning = false
            showLog()
        }
    }
    
    private func showLog() {
        let path = URL(fileURLWithPath: "/Users/\(NSUserName())/.lightning/lightning.log")
        guard let log = try? String(contentsOf: path, encoding: .utf8) else {
            print("can not get lightning.log")
            return
        }
        let logItems = log.components(separatedBy: "\n")
        DispatchQueue.main.async {
            if logItems.count > 2 {
                let lastLogItem = "\(logItems[logItems.count - 2])"
                logOutput = lastLogItem
            }
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
            task.standardOutput = stdOut
            task.standardError = stdErr
            task.launch()
            
            switch script {
            case .startLightning:
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.runScript(script: .lightingRunning)
                }
                
            case .lightningAddress:
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    getPublicUrl()
                }
               
            default:
                break
            }
                        
            task.waitUntilExit()
            
            let data = stdOut.fileHandleForReading.readDataToEndOfFile()
            let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
            var result = ""
            
            if let output = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("output: \(output)")
                #endif
                result += output
            } else {
                print("data.count: \(data.count)")
            }
            
            switch script {
            case .getRune, .lightningNodeId:
                parseDataResponse(script: script, data: data)
                
            default:
                break
            }
            
            if let errorOutput = String(data: errData, encoding: .utf8) {
                #if DEBUG
                print("error: \(errorOutput)")
                #endif
                
                if errorOutput != "", !errorOutput.contains("Your account is limited to 1 simultaneous ngrok agent sessions") {
                    showMessage(message: errorOutput)
                    isAnimating = false
                } else {
                    parseScriptResult(script: script, result: result)
                }
            }
        }
    }
    
    func getPublicUrl() {
        let path = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/ngrok.log")
        guard let log = try? Data(contentsOf: path) else {
            print("Unable to get ngrok.log.")
            return
        }
        guard let stringValue = String(data: log, encoding: .utf8) else {
            print("Unable to convert log data to utf8 string.")
            return
        }
        let array = stringValue.split(separator: "\n")
        for item in array {
            if item.contains("url") {
                guard let ngrokLog = try? JSONDecoder().decode(NgrokLog.self, from: Data(item.utf8)) else {
                    print("Failed converting json to ngrokLog.")
                    return
                }
                guard let url = ngrokLog.url else {
                    print("No url from ngrok.log.")
                    return
                }
                self.publicUrl = url.replacingOccurrences(of: "tcp://", with: "")
                runScript(script: .lightningNodeId)
            }
        }
    }
    
    func parseDataResponse(script: SCRIPT, data: Data) {
        switch script {
        case .getRune:
            guard let runeResponse = dec(Rune.self, data).response as? Rune, let rune = runeResponse.rune else { return }
            let lnLink = "lnlink:\(self.nodeId)@\(self.publicUrl)?token=\(rune)"
            self.qrImage = lnLink.qrQode
            
        case .lightningNodeId:
            guard let info = dec(GetInfo.self, data).response as? GetInfo else { return }
            self.nodeId = info.id
            runScript(script: .getRune)
            
        default:
            break
        }
    }
    
    func parseScriptResult(script: SCRIPT, result: String) {
        switch script {
        case .stopLightning:
            stopLightningParse(result: result)
            
        case .lightingRunning:
            isAnimating = false
            if result.contains("Running") {
                isRunning = true
                runScript(script: .lightningAddress)
            } else if result.contains("Stopped") {
                isRunning = false
            }
            
        default:
            break
        }
        
        showLog()
    }
    
    private func dec(_ codable: Codable.Type, _ jsonData: Data) -> (response: Any?, errorDesc: String?) {
        let decoder = JSONDecoder()
        do {
            let item = try decoder.decode(codable.self, from: jsonData)
            return((item, nil))
        } catch {
            return((nil, "\(error)"))
        }
    }
    
    private func openConf(script: SCRIPT, env: [String:String], args: [String], completion: @escaping ((Bool)) -> Void) {
        #if DEBUG
        print("script: \(script.stringValue)")
        #endif
        let resource = script.stringValue
        guard let path = Bundle.main.path(forResource: resource, ofType: "command") else { return }
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
