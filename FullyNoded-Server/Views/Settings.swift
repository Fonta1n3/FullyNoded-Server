//
//  Settings.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/14/25.
//

import SwiftUI

struct Settings: View {
    
    @State var isShowing = false
    @State private var jmTagName = UserDefaults.standard.object(forKey: "tagName") as? String ?? "Unknown"
    @State private var userName = NSUserName()
    @State private var useKnots = UserDefaults.standard.value(forKey: "useKnots") as? Bool ?? false
    
    
    let bitcoinEnvValues: BitcoinEnvValues
    let knotsEnvValues: BitcoinKnotsEnvValues
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App Icon at the top
                FNIcon()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                
                // Fully Noded Server Settings
                SettingsCard(title: "Fully Noded Server Settings", systemImage: "gearshape") {
                    InfoRow(label: "Data Directory", value: Defaults.shared.fnDataDir)
                }
                
                // Bitcoin Implementation
                SettingsCard(title: "Bitcoin Implementation", systemImage: "switch.2") {
                    Picker(useKnots ? "Bitcoin Knots" : "Bitcoin Core", selection: $useKnots) {
                        Text("Bitcoin Core").tag(false)
                        Text("Bitcoin Knots").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: useKnots) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "useKnots")
                        isShowing = true
                    }
                }
                
                // Bitcoin Core Settings
                SettingsCard(title: "Bitcoin Core Settings", systemImage: "bitcoinsign.circle") {
                    InfoRow(label: "Binary name", value: bitcoinEnvValues.binaryName)
                    InfoRow(label: "Version", value: bitcoinEnvValues.version)
                    InfoRow(label: "Prefix", value: bitcoinEnvValues.prefix)
                    InfoRow(label: "Data Directory", value: Defaults.shared.bitcoinDataDir)
                    InfoRow(label: "bitcoind path", value: "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(bitcoinEnvValues.prefix)/bin/bitcoind")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    InfoRow(label: "Default RPC Ports", value: "main: 8332 | signet: 38332 | regtest: 18443 | testnet: 18332 | testnet4: 48332")
                        .foregroundColor(.secondary)
                }
                
                // Bitcoin Knots Settings
                SettingsCard(title: "Bitcoin Knots Settings", systemImage: "k.circle") {
                    InfoRow(label: "Binary name", value: knotsEnvValues.binaryName)
                    InfoRow(label: "Version", value: knotsEnvValues.version)
                    InfoRow(label: "Prefix", value: knotsEnvValues.prefix)
                    InfoRow(label: "Data Directory", value: Defaults.shared.bitcoinDataDir)
                    InfoRow(label: "bitcoind path", value: "/Users/\(userName)/.fullynoded/BitcoinKnots/\(knotsEnvValues.prefix)/bin/bitcoind")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    InfoRow(label: "Default RPC Ports", value: "main: 8332 | signet: 38332 | regtest: 18443 | testnet: 18332")
                        .foregroundColor(.secondary)
                }
                
                // JoinMarket Settings
                SettingsCard(title: "JoinMarket Settings", systemImage: "person.3") {
                    InfoRow(label: "Version", value: jmTagName)
                    InfoRow(label: "Config Location", value: "/Users/\(userName)/Library/Application Support/joinmarket/joinmarket.cfg")
                        .font(.system(.caption, design: .monospaced))
                    InfoRow(label: "Data Directory", value: "/Users/\(userName)/Library/Application Support/joinmarket")
                    InfoRow(label: "Binary location", value: "/Users/\(userName)/.fullynoded/JoinMarket")
                }
                
                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .navigationTitle("Node Configuration")
        .alert(
            "Restart required",
            isPresented: $isShowing
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ensure you stop Bitcoin and restart Fully Noded Server for the changes to take effect.")
        }
    }
}


struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.gray.opacity(0.1)))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled) // Easy copying of paths!
        }
    }
}





