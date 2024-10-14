//
//  Home.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI
import Tor

struct Home: View {
    @State private var showError = false
    @State private var message = ""
    @State private var promptToInstallXcode = false
    @State private var taggedReleases: TaggedReleases? = nil
    @State private var showingBitcoinReleases = false
    
    let showBitcoinCoreInstallButton: Bool
    let env: [String: String]
    let showJoinMarketInstallButton: Bool
    let jmTaggedReleases: TaggedReleases
    
    var body: some View {
        VStack() {
            if showBitcoinCoreInstallButton && taggedReleases == nil {
                Button {
                    runScript(script: .checkXcodeSelect, env: env)
                } label: {
                    Text("Install Bitcoin Core")
                }
            }
            
            if showingBitcoinReleases, let taggedReleases = taggedReleases {
                TaggedReleasesView(taggedReleases: taggedReleases, existingVersion: env["PREFIX"]!)
            } else if showJoinMarketInstallButton, jmTaggedReleases.count > 0 {
                JoinMarketTaggedReleasesView(taggedReleases: jmTaggedReleases, existingVersion: "xx")
            } else {
                Image("1024")
                    .resizable()
                    .cornerRadius(20.0)
                    .frame(width: 300.0, height: 300.0)
                    .padding([.all])
            }
        }
    
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        
        .onAppear(perform: {
            if TorClient.sharedInstance.state != .connected && TorClient.sharedInstance.state != .started {
                TorClient.sharedInstance.start(delegate: nil)
            }
        })
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
        #if DEBUG
        print("parse \(script.stringValue)")
        print("result: \(result)")
        #endif
        switch script {
        case .checkXcodeSelect:
            parseXcodeSelectResult(result: result)
        
        default:
            break
        }
    }
    
    private func parseXcodeSelectResult(result: String) {
        if result.contains("XCode select not installed") {
            promptToInstallXcode = true
        } else {
            promptToInstallXcode = false
            
            LatestBtcCoreRelease.get { (taggedReleases, error) in
                guard error == nil else {
                    showMessage(message: error ?? "Unknown error.")
                    return
                }
                
                guard let taggedReleases = taggedReleases else {
                    showMessage(message: error ?? "Unknown issue downloading bitcoin core releases.")
                    return
                }
                self.taggedReleases = taggedReleases
                showingBitcoinReleases = true
            }
        }
    }
}
