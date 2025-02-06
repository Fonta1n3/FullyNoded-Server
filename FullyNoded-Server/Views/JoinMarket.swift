//
//  JoinMarket.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import SwiftUI

struct JoinMarket: View {
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) var scenePhase
    @State private var statusText = "Refreshing..."
    @State private var version = UserDefaults.standard.string(forKey: "tagName") ?? ""
    @State private var startCheckingIfRunning = false
    @State private var showError = false
    @State private var message = ""
    @State private var isRunning = false
    @State private var isAnimating = false
    @State private var selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
    @State private var env: [String: String] = [:]
    @State private var isAutoRefreshing = false
    @State private var timerForStatus = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private var chains = ["main", "test", "signet", "regtest"]
    
    
    var body: some View {
        FNIcon()
        VStack() {
            HStack() {
                Image(systemName: "server.rack")
                    .padding(.leading)
                
                Text("Join Market Server v\(version)")
                Spacer()
                Button {
                    openWindow(id: "QuickConnect-JM")
                } label: {
                    Image(systemName: "qrcode")
                }
                .padding([.trailing])
                Button {
                    openWindow(id: "Utilities-JM")
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .padding([.trailing])
                Button {
                    isAutoRefreshing = false
                    isJoinMarketRunning()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .padding([.trailing])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                
                Label("Blockchain", systemImage: "network")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: 90)
                
                Text(selectedChain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: 50)
                
                if isAnimating {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                if isRunning {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                        
                        Text(statusText)
                            .onAppear {
                                isAutoRefreshing = true
                            }
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                        
                        Text("Running")
                            .onAppear {
                                isAutoRefreshing = true
                            }
                    }
                    
                } else {
                    if isAnimating {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                        
                        Text(statusText)
                            
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                        Text("Stopped")
                    }
                
                }
                if !isRunning, !isAnimating {
                    Button {
                        startJoinMarket()
                    } label: {
                        Text("Start")
                    }
                    Spacer()
                } else if !isAnimating {
                    Button {
                        stopJoinMarket()
                    } label: {
                        Text("Stop")
                    }
                    Spacer()
                }
                EmptyView()
                    .onReceive(timerForStatus) { _ in
                        isJoinMarketRunning()
                    }
            }
            .padding([.leading])
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                updateTimer(interval: 15.0)
            } else if newPhase == .inactive {
                timerForStatus.upstream.connect().cancel()
            } else if newPhase == .background {
                timerForStatus.upstream.connect().cancel()
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
        .onAppear(perform: {
            initialLoad()
        })
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func updateTimer(interval: Double) {
        timerForStatus.upstream.connect().cancel()
        timerForStatus = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
    }
   
    
    private func initialLoad() {
        env["TAG_NAME"] = UserDefaults.standard.string(forKey: "tagName") ?? ""
        selectedChain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        isJoinMarketRunning()
    }
    
    
    private func startJoinMarket() {
        isAnimating = true
        statusText = "Starting..."
        // Ensure Bitcoin Core is running before starting JM.
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            guard error == nil, let _ = result as? [String: Any] else {
                if let error = error {
                    if error.contains("Could not connect to the server") {
                        isAnimating = false
                        showMessage(message: "Looks like Bitcoin Core is not running. Please start Bitcoin Core and try again.")
                    } else {
                        startNow()
                    }
                }
                return
            }
            startNow()
        }
    }
    
    private func startNow() {
        updateTimer(interval: 3.0)
        removeLockFile()
        setEnv()
        launchJmStarter()
    }
    
    private func setEnv() {
        self.env["TAG_NAME"] = UserDefaults.standard.string(forKey: "tagName") ?? ""
    }
    
    private func launchJmStarter() {
        ScriptUtil.runScript(script: .launchJmStarter, env: self.env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
    
    // If attempting to start JM daemon when a .lock file is present in /Users/you/Library/Application Support/joinmarket will result
    // in an error.
    private func removeLockFile() {
        let fm = FileManager.default
        let path = "/Users/\(NSUserName())/Library/Application Support/joinmarket/wallets"

        if let wallets = try? fm.contentsOfDirectory(atPath: path) {
            for wallet in wallets {
                if wallet.hasSuffix(".lock") {
                    // Delete the .lock file
                    try? fm.removeItem(atPath: path + "/" + wallet)
                }
            }
        }
    }
    
    private func stopJoinMarket() {
        isAnimating = true
        updateTimer(interval: 3.0)
        ScriptUtil.runScript(script: .stopJm, env: nil, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
        
    private func isJoinMarketRunning() {
        if !isAutoRefreshing {
            isAnimating = true
            isAutoRefreshing = true
            statusText = "Refreshing..."
        }
        JMRPC.sharedInstance.command(method: .session, param: nil) { (response, errorDesc) in
            isAnimating = false
            guard errorDesc == nil else {
                if errorDesc!.contains("Could not connect to the server.") {
                    isRunning = false
                } else if !errorDesc!.contains("The request timed out.") {
                    showMessage(message: errorDesc!)
                }
                return
            }
            guard let _ = response as? [String:Any] else {
                isRunning = false
                return
            }
            isRunning = true
            updateTimer(interval: 15.0)
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
}

#Preview {
    JoinMarket()
}
