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

                    // Bitcoin Core Settings
                    SettingsCard(title: "Bitcoin Core Settings", systemImage: "bitcoinsign.circle") {
                        InfoRow(label: "Binary name", value: bitcoinEnvValues.binaryName)
                        InfoRow(label: "Version", value: bitcoinEnvValues.version)
                        InfoRow(label: "Prefix", value: bitcoinEnvValues.prefix)
                        InfoRow(label: "Data Directory", value: Defaults.shared.bitcoinCoreDataDir)
                        InfoRow(label: "bitcoind path", value: "/Users/\(NSUserName())/.fullynoded/BitcoinCore/\(bitcoinEnvValues.prefix)/bin/bitcoind")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        InfoRow(label: "Default RPC Ports", value: "main: 83322 | signet: 38332 | regtest: 18443 | testnet: 18332")
                            .foregroundColor(.secondary)
                    }

                    // Bitcoin Knots Settings
                    SettingsCard(title: "Bitcoin Knots Settings", systemImage: "k.circle") {
                        InfoRow(label: "Binary name", value: knotsEnvValues.binaryName)
                        InfoRow(label: "Version", value: knotsEnvValues.version)
                        InfoRow(label: "Prefix", value: knotsEnvValues.prefix)
                        InfoRow(label: "Data Directory", value: Defaults.shared.bitcoinKnotsDataDir)
                        InfoRow(label: "bitcoind path", value: "/Users/\(userName)/.fullynoded/BitcoinKnots/\(knotsEnvValues.prefix)/bin/bitcoind")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        InfoRow(label: "Default RPC Ports", value: "main: 8662 | signet: 38662 | regtest: 18663 | testnet: 18662")
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

                    Spacer(minLength: 40) // Extra breathing room at bottom
                }
                .padding(24)
            }
            //.background(Color(.systemBackground))
            .navigationTitle("Node Configuration")
        }
//        FNIcon()
//        
//        HStack {
//            VStack(alignment: .leading, spacing: 8) {
//                Label("Fully Noded Server Settings", systemImage: "gear")
//                Text("Data Directory: \(Defaults.shared.fnDataDir)")
//                Spacer()
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding()
//        }
//        
//        HStack {
//            VStack(alignment: .leading, spacing: 8) {
//                Label("Bitcoin Core Settings", systemImage: "gear")
//                Text("Binary name: \(bitcoinEnvValues.binaryName)")
//                Text("Version: \(bitcoinEnvValues.version)")
//                Text("Prefix: \(bitcoinEnvValues.prefix)")
//                Text("Data Directory: \(Defaults.shared.bitcoinCoreDataDir)")
//                Text("bitcoind path: /Users/\(NSUserName())/.fullynoded/BitcoinCore/\(bitcoinEnvValues.prefix)/bin/bitcoind")
//                Text("Default Knots rpcports: main 83322, signet 38332, regtest 18443, testnet 18332")
//                Spacer()
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding()
//        }
//        
//        HStack {
//            VStack(alignment: .leading, spacing: 8) {
//                Label("Bitcoin Knots Settings", systemImage: "gear")
//                Text("Binary name: \(knotsEnvValues.binaryName)")
//                Text("Version: \(knotsEnvValues.version)")
//                Text("Prefix: \(knotsEnvValues.prefix)")
//                Text("Data Directory: \(Defaults.shared.bitcoinKnotsDataDir)")
//                Text("bitcoind path: /Users/\(userName)/.fullynoded/BitcoinKnots/\(knotsEnvValues.prefix)/bin/bitcoind")
//                Text("Default Knots rpcports: main 8662, signet 38662, regtest 18663, testnet 18662")
//                Spacer()
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding()
//        }
//        
//        HStack {
//            VStack(alignment: .leading, spacing: 8) {
//                Label("Join Market Settings", systemImage: "gear")
//                Text("Version: \(jmTagName)")
//                Text("Config Location: /Users/\(userName)/Library/Application Support/joinmarket/joinmarket.cfg")
//                Text("Data Directory: /Users/\(userName)/Library/Application Support/joinmarket")
//                Text("Binary location: /Users/\(userName)/.fullynoded/JoinMarket")
//                Spacer()
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding()
//        }
//        //}
//        
//        Spacer()
    }


    
//}

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



