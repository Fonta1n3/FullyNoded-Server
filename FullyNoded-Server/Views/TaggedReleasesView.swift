//
//  TaggedReleasesView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/25/24.
//

import SwiftUI

struct TaggedReleasesView: View {
    
    @State private var showError = false
    @State private var message = ""
    @State private var taggedRelease: TaggedReleaseElement = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: 0, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
    
    let taggedReleases: TaggedReleases
    
    init(taggedReleases: TaggedReleases) {
        self.taggedReleases = taggedReleases
        self.taggedRelease = taggedReleases[0]
    }
    
    var body: some View {
        Picker("Select Bitcoin Core version to install:", selection: $taggedRelease) {
            Text("Select a release").tag(UUID())
            ForEach(taggedReleases, id: \.self) {
                Text($0.tagName ?? "")
                    .tag(Optional($0.uuid))
            }
        }
        .padding([.top, .leading, .trailing])
       
        if let author = taggedRelease.author, let login = author.login, let tagName = taggedRelease.tagName {
            Text("Written by \(login)")
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            let processedVersion = tagName.replacingOccurrences(of: "v", with: "")
            var arch = "arm64"
            #if arch(x86_64)
            arch = "x86_64"
            #endif
            //http://6hasakffvppilxgehrswmffqurlcjjjhd76jgvaqmsg6ul25s7t3rzyd.onion/
            Text(verbatim: "Downloading from http://6hasakffvppilxgehrswmffqurlcjjjhd76jgvaqmsg6ul25s7t3rzyd.onion/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz")
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack() {
                let url = "https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-\(tagName.replacingOccurrences(of: "v", with: "")).md"
                
                Link("Release Notes", destination: URL(string: url)!)
            }
            .padding([.leading, .bottom])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                install(taggedRelease)
            } label: {
                Text("Install Bitcoin Core \(tagName)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
        }
        
        Spacer()
        
            .onAppear {
                taggedRelease = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: nil, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
            }
        
        
        
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func install(_ taggedRelease: TaggedReleaseElement) {
        let processedVersion = taggedRelease.tagName!.replacingOccurrences(of: "v", with: "")
        var arch = "arm64"
        #if arch(x86_64)
        arch = "x86_64"
        #endif
        
        let onion = "http://6hasakffvppilxgehrswmffqurlcjjjhd76jgvaqmsg6ul25s7t3rzyd.onion"
        let macOSUrl = "\(onion)/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
        
//        let dict: [String: Any] = [
//            "version":"\(processedVersion)",
//            "binaryPrefix":"bitcoin-\(processedVersion)",
//            "macosBinary":"bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz",
//            "macosURL":"\(onion)/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
//            "shaURL":"\(onion)/bin/bitcoin-core-\(processedVersion)/SHA256SUMS",
//            "shasumsSignedUrl":"\(onion)/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
//        ]
        
//        DataManager.saveEntity(entityName: "BitcoinEnv", dict: dict) { saved in
//            guard saved else {
//                return
//            }
            
            InstallBitcoinCore.checkExistingConf { ready in
                if ready {
                    print("hello")
                    var request = URLRequest(url: URL(string: macOSUrl)!)
                    request.httpMethod = "GET"
                    request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                    
                    let task = TorClient.sharedInstance.session.dataTask(with: request as URLRequest) { (data, response, error) in
                        if let error = error {
                            showMessage(message: error.localizedDescription)
                        }
                        
                        guard let urlContent = data else {
                            //completion((nil, error?.localizedDescription))
                            
                            
                            return
                        }
                        
                        let filePath = URL(fileURLWithPath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz")
                        
                        
                        do {
                            try urlContent.write(to: filePath)
                            print("saved urlContent")
                        } catch {
                            print("failed")
                        }
                    }
                    task.resume()
                    // Set timer to see if install was successful
                    //startCheckingForBitcoinInstall = true
                } else {
                    print("not ready")
                }
            }
            
            
        //}
    }
    
    
}
