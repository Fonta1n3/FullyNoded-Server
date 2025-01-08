//
//  QuickConnectView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/8/25.
//

import SwiftUI

struct QuickConnectView: View {
    
    @State private var qrImage: NSImage? = nil
    @State private var rpcAuth = ""
    @State private var showError = false
    @State private var message = ""
    @State private var fullyNodedUrl: String?
    @State private var unifyUrl: String?
    @State private var fnBcoreUrl: String?
    
    var body: some View {
        Spacer()
            VStack() {
                HStack() {
                    Label("Quick Connect", systemImage: "qrcode")
                        .padding([.leading])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Button {
                        showMessage(message: "The Quick Connect QR exports your rpc hostname (an onion or localhost) and the rpc port (combined these make up your nodes rpc address) which is required for FN to connect.\n\nThis QR does *NOT* include the FN-Server RPC credentials (it includes a dummy rpc user and password for security).\n\nYou must export and authorize your rpc user from FN mobile apps to FN-Server to complete your connection.\n\nTo do this: In FN navigate to Node Manager > + > Scan QR > update the rpc password in Node Credentials > Save the node > Export the rpcauth text from FN and use the text field to add it to your bitcoin.conf.")
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .padding([.trailing])
                }
                
                
                Button("Connect Fully Noded", systemImage: "qrcode") {
                    connectFN()
                }
                .padding([.leading, .trailing])
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack() {
                    Text("Authorize an additional RPC user:")
                        .padding([.leading])
                    TextField("rpcauth=FullyNoded:xxxx$xxxx", text: $rpcAuth)
                        .padding([])
                    if rpcAuth != "" {
                        Button {
                            if addRpcAuthToConf() {
                                rpcAuth = ""
                                showMessage(message: "RPC user authorized. You will need to restart your node for the change to take effect.")
                            }
                        } label: {
                            Text("Add RPC auth")
                        }
                    }
                    Spacer()
                }
                
                if let qrImage = qrImage {
                    Image(nsImage: qrImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                }
                
                if let fullyNodedUrl = fullyNodedUrl {
                    Link("Connect Fully Noded (locally)", destination: URL(string: fullyNodedUrl)!)
                        .padding([.leading])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let fnBcoreUrl = fnBcoreUrl {
                    Link("Connect Fully Noded - Bitcoin Core (locally)", destination: URL(string: fnBcoreUrl)!)
                        .padding([.leading])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let unifyUrl = unifyUrl {
                    Link("Connect Unify (locally)", destination: URL(string: unifyUrl)!)
                        .padding([.leading, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary, lineWidth: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.leading, .trailing])
            )
        Spacer()
        Spacer()
            .alert(message, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func bitcoinConf() -> String? {
        return conf(stringPath: bitcoinConfPath())
    }
    
    private func bitcoinConfPath() -> String {
        let dataDir = Defaults.shared.dataDir
        return dataDir + "/bitcoin.conf"
    }
    
    private func addRpcAuthToConf() -> Bool {
        guard let conf = bitcoinConf() else {
            return false
        }
        
        let newConf = """
                    \(rpcAuth)
                    \(conf)
                    """
        guard writeBitcoinConf(newConf: newConf) else {
            showMessage(message: "Can not write to bitcoin.conf.")
            return false
        }
        
        return true
    }
    
    private func writeBitcoinConf(newConf: String) -> Bool {
        return ((try? newConf.write(to: URL(fileURLWithPath: bitcoinConfPath()), atomically: false, encoding: .utf8)) != nil)
    }
    
    private func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func conf(stringPath: String) -> String? {
        guard fileExists(path: stringPath) else {
            #if DEBUG
            print("file does not exists at: \(stringPath)")
            #endif
            return nil
        }
        
        let url = URL(fileURLWithPath: stringPath)
        if let conf = try? Data(contentsOf: url) {
            guard let string = String(data: conf, encoding: .utf8) else {
                showMessage(message: "Can not encode data as utf8 string.")
                return nil
            }
            return string
        } else if let conf = try? String(contentsOf: url) {
            return conf
        } else {
            showMessage(message: "No contents found.")
            return nil
        }
    }
    
    private func connectFN() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            showMessage(message: "No hostnames. Please report this.")
            return
        }
        var onionHost = ""
        let chain = UserDefaults.standard.string(forKey: "chain") ?? "main"
        
         switch chain {
         case "main":
             onionHost = hiddenServices[1] + ":" + "8332"
         case "test":
             onionHost = hiddenServices[2] + ":" + "18332"
         case "signet":
             onionHost = hiddenServices[3] + ":" + "38332"
         case "regtest":
             onionHost = hiddenServices[3] + ":" + "18443"
         default:
             break
         }
        
        DataManager.retrieve(entityName: .rpcCreds) { rpcCred in
            guard let _ = rpcCred else {
                showMessage(message: "No rpc credentials saved.")
                return
            }
            
            let url = "http://xxx:xxx@\(onionHost)"
            qrImage = url.qrQode
            
            let port = UserDefaults.standard.object(forKey: "port") as? String ?? "8332"
            self.fullyNodedUrl = "btcrpc://xxx:xxx@localhost:\(port)"
            self.unifyUrl = "unify://xxx:xxx@localhost:\(port)"
            self.fnBcoreUrl = "fnbtccore://xxx:xxx@localhost:\(port)"
        }
    }
}

#Preview {
    QuickConnectView()
}
