//
//  Help.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 12/4/24.
//

import SwiftUI

struct Help: View {
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App Icon at the top
                    FNIcon()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    // Support Section
                    SupportCard(title: "Need support?", systemImage: "questionmark.circle") {
                        LinkRow(text: "Let us know about an issue, bug, feature request or general comments here.", destination: URL(string: "https://github.com/Fonta1n3/FullyNoded-Server/issues/new")!)
                    }

                    // Website Section
                    SupportCard(title: "Visit our website", systemImage: "globe") {
                        LinkRow(text: "www.FullyNoded.app", destination: URL(string: "https://www.FullyNoded.app")!)
                    }

                    // Chat Section
                    SupportCard(title: "Come chat", systemImage: "bubble.left.and.bubble.right") {
                        LinkRow(text: "Join the Telegram", destination: URL(string: "https://t.me/FullyNoded")!)
                        LinkRow(text: "Join the Discord", destination: URL(string: "https://discord.gg/TVf2zb9x")!)
                        LinkRow(text: "Follow us on X", destination: URL(string: "https://x.com/FullyNoded")!)
                    }

                    // Download Links Section
                    SupportCard(title: "Download Links", systemImage: "arrow.down.circle") {
                        LinkRow(text: "Fully Noded", destination: URL(string: "https://apps.apple.com/us/app/fully-noded/id1436425586")!)
                        LinkRow(text: "Fully Noded - Join Market", destination: URL(string: "https://apps.apple.com/us/app/fully-noded-join-market/id6651860963")!)
                        LinkRow(text: "Unify - Payjoin Wallet", destination: URL(string: "https://apps.apple.com/us/app/unify-payjoin-wallet/id6504735719")!)
                        LinkRow(text: "Plasma - Core Lightning Wallet", destination: URL(string: "https://apps.apple.com/us/app/plasma-core-lightning-wallet/id6468914352")!)
                    }

                    Spacer(minLength: 40) // Extra breathing room at bottom
                }
                .padding(24)
            }
            //.background(Color(.systemBackground))
            .navigationTitle("Support & Links")
    }
}

struct SupportCard<Content: View>: View {
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

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.gray.opacity(0.1)))  // Assuming you have the extension from before
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
    }
}

struct LinkRow: View {
    let text: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.body)
                    .foregroundColor(.accentColor)
                Image(systemName: "link")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle()) // Keeps it looking like a link, not a button
    }
}

#Preview {
    Help()
}
