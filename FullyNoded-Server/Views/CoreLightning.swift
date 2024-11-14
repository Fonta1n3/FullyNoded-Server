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
    @State private var lnlink: String?
    @State private var localLnlink: String?
    @State private var plasmaExists = false
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var onionHost: String? = nil
    @State private var quickConnectClnRest: String? = nil
    
    var body: some View {
        FNIcon()
        VStack() {
            HStack() {
                Image(systemName: "server.rack")
                    .padding(.leading)
                
                Text("Core Lightning Server v24.08.1")
                Spacer()
                Button {
                    isLightningOn()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .padding(.trailing)
            }
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
                        Text("Stopping...")
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .padding(.leading)
                        Text("Running")
                    }
                    
                } else {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                            .padding(.leading)
                        Text("Starting...")
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .padding(.leading)
                        Text("Stopped")
                    }
                    
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
        }
        .padding()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .trailing])
        )
        
        VStack() {
            Label("Network", systemImage: "network")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(selectedChain)
                .padding([.leading])
                .padding(.leading)
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
        
        VStack() {
            Label("Utilities", systemImage: "wrench.and.screwdriver")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                Button {
                    let env = ["FILE":"/Users/\(NSUserName())/.lightning/config"]
                    openFile(env: env)
                } label: {
                    Text("Config")
                }
                .padding(.leading)
                
                Button {
                    let env = ["FILE":"/Users/\(NSUserName())/.lightning/lightning.log"]
                    openFile(env: env)
                } label: {
                    Text("Log")
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
        
        VStack() {
            Label("Quick Connect", systemImage: "qrcode")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Connect Plasma remotely via LNLink", systemImage: "qrcode") {
                getLnLink(isLocal: false)
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
                            self.lnlink = nil
                        }
                    }
            }
            
            Button("Connect via Onion (clnrest-rs)", systemImage: "qrcode") {
                self.onionHost = TorClient.sharedInstance.hostnames()?[5]
                ScriptUtil.runScript(script: .getRune, env: nil, args: nil) { (output, rawData, errorMessage) in
                    guard errorMessage == nil else {
                        if errorMessage != "" {
                            showMessage(message: errorMessage!)
                        } else if let data = rawData {
                            parseRuneResponse(data: data)
                        }
                        return
                    }
                    guard let output = output, let data = rawData else { return }
                    parseRuneResponse(data: data)
                }
            }
            .padding([.leading])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let quickConnectClnRest = self.quickConnectClnRest {
                let qr = quickConnectClnRest.qrQode
                Image(nsImage: qr)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                            self.quickConnectClnRest = nil
                            self.onionHost = nil
                            self.lnlink = nil
                        }
                    }
                if let onionHost = onionHost {
                    Text(onionHost)
                        .textSelection(.enabled)
                }
            }
            
            if plasmaExists {
                Button("Connect Plasma Locally") {
                    getLnLink(isLocal: true)
                }
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if let lnlink = self.localLnlink {
                    Link("Connect Plasma Locally via LNLink", destination: URL(string: lnlink)!)
                        .padding([.leading])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
            } else {
                Link("Download Plasma", destination: URL(string: "https://apps.apple.com/us/app/plasma-core-lightning-wallet/id6468914352")!)
                    .padding([.leading])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .trailing])
        )
        Spacer()
        Label {
            Text(logOutput)
                .foregroundStyle(.green)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.green)
        }
        .padding(.all)
        .foregroundStyle(.secondary)
        .onAppear(perform: {
            isLightningOn()
            checkIfPlasmaExists()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func openFile(env: [String: String]?) {
        ScriptUtil.runScript(script: .openFile, env: env, args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    private func checkIfPlasmaExists() {
        guard let filePaths = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") else { return }
        for filePath in filePaths {
            if filePath == "Plasma.app" {
                plasmaExists = true
            }
        }
    }
    
    private func showQr() {
        getPublicUrl(isLocal: false)
    }
    
    private func parseLightningRunning(output: String) {
        isAnimating = false
        if output.contains("Running") {
            isRunning = true
        } else if output.contains("Stopped") {
            isRunning = false
        }
    }
    
    private func startLightning() {
        isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            ScriptUtil.runScript(script: .lightingRunning, env: nil, args: nil) { (output, rawData, errorMessage) in
                guard errorMessage == nil else {
                    if errorMessage != "" {
                        showMessage(message: errorMessage!)
                    } else if let output = output {
                        parseLightningRunning(output: output)
                    }
                    return
                }
                guard let output = output else { return }
                parseLightningRunning(output: output)
            }
        }
        ScriptUtil.runScript(script: .startLightning, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    private func isLightningOn() {
        isAnimating = true
        ScriptUtil.runScript(script: .lightingRunning, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else if let output = output {
                    parseLightningRunning(output: output)
                }
                return
            }
            guard let output = output else { return }
            parseLightningRunning(output: output)
        }
    }
    
    private func stopLightning() {
        isAnimating = true
        ScriptUtil.runScript(script: .stopLightning, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else if let output = output {
                    stopLightningParse(result: output)
                }
                return
            }
            guard let output = output else { return }
            stopLightningParse(result: output)
        }
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
    
    func getLnLink(isLocal: Bool) {
        ScriptUtil.runScript(script: .lightningNodeId, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard let data = rawData else {
                return
            }
            
            guard let info = dec(GetInfo.self, data).response as? GetInfo else { return }
            self.nodeId = info.id
            getRune(isLocal: isLocal)
        }
    }
    
    func getRune(isLocal: Bool) {
        ScriptUtil.runScript(script: .getRune, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard let data = rawData else { return }
            guard let runeResponse = dec(Rune.self, data).response as? Rune, let rune = runeResponse.rune else { return }
            if !isLocal {
                let publicLnLink = "lnlink:\(self.nodeId)@\(self.publicUrl)?token=\(rune)"
                if publicUrl != "" {
                    self.qrImage = publicLnLink.qrQode
                }
            } else {
                self.localLnlink = "lnlink:\(self.nodeId)@127.0.0.1:9735?token=\(rune)"
            }
            if let onionHost = self.onionHost {
                self.quickConnectClnRest = "clnrest://\(onionHost):18765?token=\(rune)"
            }
        }
    }
    
    func getPublicUrl(isLocal: Bool) {
        if isLocal {
            self.publicUrl = "127.0.0.1:9735"
            getNodeID()
        } else {
            let path = URL(fileURLWithPath: "/Users/\(NSUserName())/.lightning/config")
            guard let config = try? Data(contentsOf: path) else {
                print("Unable to get ngrok.log.")
                return
            }
            guard let stringValue = String(data: config, encoding: .utf8) else {
                print("Unable to convert log data to utf8 string.")
                return
            }
            let array = stringValue.split(separator: "\n")
            var anyAddr = false
            for item in array {
                if item.hasPrefix("addr=") {
                    anyAddr = true
                    let itemArr = item.split(separator: "=")
                    self.publicUrl = "\(itemArr[1])"
                    getNodeID()
                }
            }
            if !anyAddr {
                getNodeID()
                showMessage(message: "In order to connect via QR code remotely with Plasma you need to open the lightning config and add addr=<your public IP address>, example: addr=100.89.65.23:9735. If you do not have a public IP you can use Plasma locally by clicking \"Connect Plasma Locally\".")
            }
        }
        
    }
    
    private func getNodeID() {
        ScriptUtil.runScript(script: .lightningNodeId, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                } else if let data = rawData {
                    parseLigtningNodeId(data: data)
                }
                return
            }
            guard let data = rawData else { return }
            parseLigtningNodeId(data: data)
        }
    }
    
    private func parseLigtningNodeId(data: Data) {
        guard let info = dec(GetInfo.self, data).response as? GetInfo else { return }
        self.nodeId = info.id
    }
    
    private func parseRuneResponse(data: Data) {
        guard let runeResponse = dec(Rune.self, data).response as? Rune, let rune = runeResponse.rune else { return }
        let publicLnLink = "lnlink:\(self.nodeId)@\(self.publicUrl)?token=\(rune)"
        if publicUrl != "" {
            self.qrImage = publicLnLink.qrQode
        }
        self.localLnlink = "lnlink:\(self.nodeId)@127.0.0.1:9735?token=\(rune)"
        if let onionHost = self.onionHost {
            self.quickConnectClnRest = "clnrest://\(onionHost):18765?token=\(rune)"
        }
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
}
