//
//  Home.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI


struct Home: View {
    @State private var showError = false
    @State private var message = ""
    @State private var taggedReleases: TaggedReleases? = nil
    @State private var showingBitcoinReleases = false
    @State private var showingKnotsReleases = false
    
    let showBitcoinCoreInstallButton: Bool
    let showBitcoinKnotsInstallButton: Bool
    let env: [String: String]
    let showJoinMarketInstallButton: Bool
    let jmTaggedReleases: TaggedReleases
    
    var body: some View {
        VStack() {
            if taggedReleases == nil {
                if showBitcoinKnotsInstallButton {
                    Button {
                        getLatestBtcKnots()
                    } label: {
                        Text("Install Bitcoin Knots")
                    }
                    
                } else if showBitcoinCoreInstallButton {
                    Button {
                        getLatestBtcCore()
                    } label: {
                        Text("Install Bitcoin Core")
                    }
                }
            }
            
            
            if showingBitcoinReleases, let taggedReleases = taggedReleases {
                TaggedReleasesBitcoinCoreView(taggedReleasesBitcoinCore: taggedReleases, existingVersion: env["PREFIX"]!)
                
//            } else if showingKnotsReleases, let taggedReleases = taggedReleases {
//                TaggedReleasesBitcoinKnotsView(taggedReleasesBitcoinKnots: taggedReleases, existingVersion: env["PREFIX"]!)
                
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
    
    private func getLatestBtcKnots() {
        LatestBtcKnotsRelease.get { (taggedReleases, error) in
            guard error == nil else {
                showMessage(message: error ?? "Unknown error.")
                return
            }
            
            guard let taggedReleases = taggedReleases else {
                showMessage(message: error ?? "Unknown issue downloading bitcoin knots releases.")
                return
            }
            self.taggedReleases = taggedReleases
            showingKnotsReleases = true
        }
    }
    
    private func getLatestBtcCore() {
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
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
}
