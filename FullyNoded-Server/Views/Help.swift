//
//  Help.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 12/4/24.
//

import SwiftUI

struct Help: View {
    var body: some View {
        VStack() {
            Text("Need support?")
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading, .top])
            Link("Let us know about an issue, bug, feature request or general comments here.", destination: URL(string: "https://github.com/Fonta1n3/FullyNoded-Server/issues/new")!)
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Text("Visit our website")
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            Link("www.FullyNoded.app", destination: URL(string: "https://www.FullyNoded.app")!)
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Text("Come chat")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Link("Join the Telegram", destination: URL(string: "https://t.me/FullyNoded")!)
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Link("Join the Discord", destination: URL(string: "https://discord.gg/TVf2zb9x")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading, .bottom])
            Text("Download Links")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Link("Fully Noded - Original", destination: URL(string: "https://apps.apple.com/us/app/fully-noded/id1436425586")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            Link("Fully Noded - Bitcoin Core", destination: URL(string: "https://apps.apple.com/us/app/fn-bitcoin-core/id6450649419")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            Link("Fully Noded - Join Market", destination: URL(string: "https://apps.apple.com/us/app/fully-noded-join-market/id6651860963")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            Link("Unify - Payjoin Wallet", destination: URL(string: "https://apps.apple.com/us/app/unify-payjoin-wallet/id6504735719")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            Link("Plasma - Core Lightning Wallet", destination: URL(string: "https://apps.apple.com/us/app/plasma-core-lightning-wallet/id6468914352")!)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.leading])
            
            Spacer()
        }
    }
}

#Preview {
    Help()
}
