//
//  Settings.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/14/25.
//

import SwiftUI

struct Settings: View {
    
    @State var isShowing = false
    
    let bitcoinEnvValues: BitcoinEnvValues
    
    var body: some View {
        Text("Settings")
        Text("Binary name: \(bitcoinEnvValues.binaryName)")
        Text("Version: \(bitcoinEnvValues.version)")
        Text("Prefix: \(bitcoinEnvValues.prefix)")
        Text("Bitcoin data directory: \(Defaults.shared.bitcoinCoreDataDir)")
        Text("Fully Noded Server data directory: \(Defaults.shared.fnDataDir)")
        Text("bitcoind path: /Users/\(NSUserName())/.fullynoded/BitcoinCore/\(bitcoinEnvValues.prefix)/bin/bitcoind")
        
        /*
         let dict = [
             "binaryName": "bitcoin-27.2-arm64-apple-darwin.tar.gz",
             "version": "27.2",
             "prefix": "bitcoin-27.2",
             "dataDir": Defaults.shared.dataDir,
             "chain": Defaults.shared.chain
         ]
         */
        VStack {
                   Button {
                       isShowing.toggle()
                   } label: {
                       Text("documents")
                   }
                   .fileImporter(isPresented: $isShowing, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: { results in
                       
                       switch results {
                       case .success(let fileurls):
                           guard fileurls.count == 1 else {
                               print("Too many/few files exist here, select the bitcoind binary only.")
                               return
                           }
                           
                           let fileurl = fileurls[0]
                           
                           guard fileurl.absoluteString.hasSuffix("/bitcoind") else {
                               print("Not bitcoind.")
                               return
                           }
                           
                           print("User selected bitcoind.")
                           
                       case .failure(let error):
                           print(error)
                       }
                   })
               }
    }
}

//#Preview {
//    Settings()
//}
