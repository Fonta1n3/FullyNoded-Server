//
//  JMQuickConnectView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/6/25.
//

import SwiftUI

struct JMQuickConnectView: View {
    
    @State private var qrImage: NSImage? = nil
    @State private var showError = false
    @State private var message = ""
    @State private var url: String?
    
    var body: some View {
        VStack() {
            Label("Quick Connect", systemImage: "qrcode")
                .padding([.leading])
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Connect Fully Noded - Join Market", systemImage: "qrcode") {
                showConnectUrls()
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let qrImage = qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    .onAppear {
                        hideQrData()
                    }
                if let url = url {
                    Link("Connect Fully Noded - Join Market (locally)", destination: URL(string: url)!)
                        .padding([.leading, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func hideQrData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.qrImage = nil
            self.url = nil
        }
    }
    
    private func showConnectUrls() {
        guard let hiddenServices = TorClient.sharedInstance.hostnames() else {
            showMessage(message: "No hostnames.")
            return
        }
        let host = hiddenServices[0] + ":" + "28183"
        
        let certPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/ssl/cert.pem"
        if FileManager.default.fileExists(atPath: certPath) {
            guard var cert = try? String(contentsOf: URL(fileURLWithPath: certPath)) else {
                showMessage(message: "No joinmarket cert.")
                return
            }
            cert = cert.replacingOccurrences(of: "\n", with: "")
            cert = cert.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            cert = cert.replacingOccurrences(of: " ", with: "")
            let quickConnectUrl = "http://" + host + "?cert=\(cert.urlSafeB64String)"
            self.url = "joinmarket://localhost:28183?cert=\(cert.urlSafeB64String)"
            qrImage = quickConnectUrl.qrQode
        }
    }
}

#Preview {
    JMQuickConnectView()
}
