//
//  JMUtilsView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/6/25.
//

import SwiftUI

struct JMUtilsView: View {
    
    @Environment(\.openURL) var openURL
    @State private var showError = false
    @State private var message = ""
    @State private var env: [String: String] = [:]
    @State private var promptToReindex = false
    @State private var isAnimating = false
    @State private var promptToIncreaseGapLimit = false
    @State private var orderBookOpened = false
    @State private var walletName = ""
    @State private var gapLimit = ""
    
    var body: some View {
        Spacer()
        VStack() {
            Label("Utilities", systemImage: "wrench.and.screwdriver")
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                Button {
                    openFile(file: "joinmarket.cfg")
                } label: {
                    Text("joinmarket.cfg")
                }
                Button {
                    confirgureJm()
                } label: {
                    Text("Configure JM")
                }
                Button {
                    openDataDir()
                } label: {
                    Text("Data Dir")
                }
                Button {
                    promptToIncreaseGapLimit = true
                } label: {
                    Text("Increase gap limit")
                }
                Button {
                    rescan()
                } label: {
                    Text("Rescan")
                }
                Button {
                    orderBook()
                } label: {
                    Text("Order Book")
                }
//                Button {
//                    refreshConfig()
//                } label: {
//                    Text("Refresh Config")
//                }
                
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
        .alert(message, isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Increase the gap limit to? (upon completion a rescan will be required).", isPresented: $promptToIncreaseGapLimit) {
            TextField("Enter the new gap limit", text: $gapLimit)
            TextField("Enter the wallet name", text: $walletName)
            Button("OK", action: increaseGapLimit)
        }
        .alert("The order book launches a terminal (see output if any issues and report) and opens the browser at http://localhost:62601 to display the current order book.", isPresented: $orderBookOpened) {
            Button("Open", action: openOrderBookNow)
        }
        Spacer()
        Spacer()
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func confirgureJm() {
        ConfigureJM.configureJm { (configured, error) in
            guard configured else {
                showMessage(message: error ?? "Unknown error configuring Join Market.")
                return
            }
            showMessage(message: "Join Market configured ✓")
        }
    }
    
    private func openOrderBookNow() {
        ScriptUtil.runScript(script: .launchObWatcher, env: ["TAG_NAME": tagName], args: nil) { (output, _, errorMessage) in
            guard let errorMess = errorMessage, errorMess != "" else {
                openURL(URL(string: "http://localhost:62601")!)
                return
            }
            showMessage(message: errorMess)
        }
    }
    
    private var tagName: String {
        return  UserDefaults.standard.object(forKey: "tagName") as? String ?? ""
    }
    
    private func increaseGapLimit() {
        if !walletName.hasSuffix(".jmdat") {
            walletName += ".jmdat"
        }
        let env: [String: String] = ["TAG_NAME": tagName, "GAP_AMOUNT": gapLimit, "WALLET_NAME": walletName]
        ScriptUtil.runScript(script: .launchIncreaseGapLimit, env: env, args: nil) { (output, rawData, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
            showMessage(message: "Gap limit increased, check the script output to be sure.")
        }
    }
    
    private func orderBook() {
        orderBookOpened = true
    }
    
    private func rescan() {
        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
            guard error == nil, let result = result as? [String: Any] else {
                showMessage(message: error ?? "Unknown error getblbockchaininfo.")
                return
            }
            guard let pruneheight = result["pruneheight"] as? Int else {
                showMessage(message: "No pruneheight")
                return
            }
            
            BitcoinRPC.shared.command(method: "rescanblockchain", params: ["start_height": pruneheight]) { (result, error) in
                guard error == nil, let _ = result as? [String: Any] else {
                    showMessage(message: error ?? "Unknown error rescanblockchain.")
                    return
                }
            }
            // No response from core when initiating a rescan...
            showMessage(message: "Blockchain rescan started.")
        }
    }
    
    private func openDataDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Users/\(NSUserName())/Library/Application Support/joinmarket")
    }
    
    private func openFile(file: String) {
        let fileEnv = ["FILE": "/Users/\(NSUserName())/Library/Application Support/joinmarket/\(file)"]
        ScriptUtil.runScript(script: .openFile, env: fileEnv, args: nil) { (_, _, errorMessage) in
            guard errorMessage == nil else {
                if errorMessage != "" {
                    showMessage(message: errorMessage!)
                }
                return
            }
        }
    }
}

#Preview {
    JMUtilsView()
}
