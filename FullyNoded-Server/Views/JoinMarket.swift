//
//  JoinMarket.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import SwiftUI

struct JoinMarket: View {
    
    @State private var version = UserDefaults.standard.string(forKey: "tagName") ?? ""
    @State private var qrImage: NSImage? = nil
    @State private var startCheckingIfRunning = false
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var logOutput = ""
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var url: String?
    @State private var isAutoRefreshing = false
    private let timerForStatus = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private var chains = ["main", "test", "signet", "regtest"]
    
    
    var body: some View {
        HStack() {
            Image(systemName: "server.rack")
                .padding(.leading)
            
            Text("Join Market Server")
            Spacer()
            
            Button {
                isAutoRefreshing = false
                isJoinMarketRunning()
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
                    .onAppear {
                        isAutoRefreshing = true
                    }
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
                    startJoinMarket()
                } label: {
                    Text("Start")
                }
            } else {
                Button {
                    stopJoinMarket()
                } label: {
                    Text("Stop")
                }
            }
            EmptyView()
                .onReceive(timerForStatus) { _ in
                    isJoinMarketRunning()
                }
        }
        .padding([.leading, .bottom])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label(selectedChain.capitalized, systemImage: "network")
            .padding([.leading, .bottom])
            .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Utilities", systemImage: "wrench.and.screwdriver")
            .padding(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack() {
            Button {
                openFile(file: "joinmarket.cfg")
            } label: {
                Text("joinmarket.cfg")
            }
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Label("Quick Connect", systemImage: "qrcode")
            .padding([.leading, .top])
            .frame(maxWidth: .infinity, alignment: .leading)
        
        Button("Connect Fully Noded - Join Market", systemImage: "qrcode") {
            showConnectUrls()
        }
        .padding([.leading, .trailing])
        .frame(maxWidth: .infinity, alignment: .leading)
        
        if let qrImage = qrImage {
            Image(nsImage: qrImage)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        self.qrImage = nil
                    }
                }
            if let url = url {
                Link("Connect Fully Noded - Join Market", destination: URL(string: url)!)
                    .padding([.leading, .bottom])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
        Spacer()
        
        HStack() {
            Label(logOutput, systemImage: "info.circle")
                .padding(.all)
        }
        .onAppear(perform: {
            selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
            isJoinMarketRunning()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func showConnectUrls() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            showMessage(message: "No hostnames.")
            return
        }
        let host = hiddenServices[0] + ":" + "28183"
        
        let certPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/ssl/cert.pem"
        if FileManager.default.fileExists(atPath: certPath) {
            guard var cert = try? String(contentsOf: URL(fileURLWithPath: certPath)) else {
                showMessage(message: "No joinmarket cert.")
                return
            }
            cert = cert.replacingOccurrences(of: "\n", with: "")
            cert = cert.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: " ", with: "")
            let quickConnectUrl = "http://" + host + "?cert=\(cert.urlSafeB64String)"
            self.url = "joinmarket://localhost:28183?cert=\(cert.urlSafeB64String)"
            qrImage = quickConnectUrl.qrQode
        }
    }
    
    private func openFile(file: String) {
        let env = ["FILE": "/Users/\(NSUserName())/Library/Application Support/joinmarket/\(file)"]
        
        openConf(script: .openFile, env: env, args: []) { _ in }
    }
        
    private func startJoinMarket() {
        isAnimating = true
        env["TAG_NAME"] = UserDefaults.standard.string(forKey: "tagName") ?? ""
        runScript(script: .launchJmStarter)
    }
    
    private func stopJoinMarket() {
        runScript(script: .stopJm)
    }
    
        
    private func isJoinMarketRunning() {
        if !isAutoRefreshing {
            isAnimating = true
            isAutoRefreshing = true
        }
        JMRPC.sharedInstance.command(method: .session, param: nil) { (response, errorDesc) in
            isAnimating = false
            guard errorDesc == nil else {
                if errorDesc!.contains("Could not connect to the server.") {
                    isRunning = false
                } else if !errorDesc!.contains("The request timd out.") {
                    showMessage(message: errorDesc!)
                }
                return
            }
            guard let _ = response as? [String:Any] else {
                isRunning = false
                return
            }
            isRunning = true
            
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
        }
    }
    
    private func openConf(script: SCRIPT, env: [String:String], args: [String], completion: @escaping ((Bool)) -> Void) {
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
            result += output
            completion(true)
        } else {
            completion(false)
        }
    }
}

#Preview {
    JoinMarket()
}
