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
                .padding([.leading])
            Spacer()
        }
    }
}

#Preview {
    Help()
}
