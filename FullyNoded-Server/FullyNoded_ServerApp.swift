//
//  FullyNoded_ServerApp.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

@main
struct FullyNoded_ServerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if UserDefaults.standard.value(forKey: "encKeyFullyNodedServer") as? String == nil {
                        UserDefaults.standard.setValue(Crypto.privKeyData().base64EncodedString(), forKey: "encKeyFullyNodedServer")
                    }
                }
        }
        Window("Utilities", id: "Utilities") {
            //Text("New in this version…")
            BtcUtilsView()
        }
        Window("QuickConnect", id: "QuickConnect") {
            QuickConnectView()
        }
        
    }
}
