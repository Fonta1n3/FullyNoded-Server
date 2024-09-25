//
//  TaggedReleasesView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/25/24.
//

import SwiftUI

struct TaggedReleasesView: View {
    
    @State private var isAnimating = false
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
            
            HStack() {
                if isAnimating {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                
                Button {
                    install(taggedRelease, useTor: false)
                } label: {
                    Text("Install Bitcoin Core \(tagName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
        }
        
        Spacer()
        
            .onAppear {
                taggedRelease = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: nil, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
            }
        
            .alert(message, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        
        
        
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func install(_ taggedRelease: TaggedReleaseElement, useTor: Bool) {
        let processedVersion = taggedRelease.tagName!.replacingOccurrences(of: "v", with: "")
        var arch = "arm64"
        #if arch(x86_64)
        arch = "x86_64"
        #endif
        
        let onion = "http://6hasakffvppilxgehrswmffqurlcjjjhd76jgvaqmsg6ul25s7t3rzyd.onion"
        let clearnet = "https://bitcoincore.org"
        var macOSUrl = "\(onion)/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
        
        if !useTor {
            macOSUrl = "\(clearnet)/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
        }
        
//        let dict: [String: Any] = [
//            "version":"\(processedVersion)",
//            "binaryPrefix":"bitcoin-\(processedVersion)",
//            "macosBinary":"bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz",
//            "macosURL":"\(onion)/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
//            "shaURL":"\(onion)/bin/bitcoin-core-\(processedVersion)/SHA256SUMS",
//            "shasumsSignedUrl":"\(onion)/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
//        ]
        

            
        InstallBitcoinCore.checkExistingConf { ready in
            if ready {
                isAnimating = true
                let task = TorClient.sharedInstance.session.downloadTask(with: URL(string: macOSUrl)!) { localURL, urlResponse, error in
                    isAnimating = false
                    
                    if let localURL = localURL {
                        if let data = try? Data(contentsOf: localURL) {
                            print(localURL)
                            let filePath = URL(fileURLWithPath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz")
                            guard ((try? data.write(to: filePath)) != nil) else {
                                return
                            }
                            print("saved urlContent")
//                                //        DataManager.saveEntity(entityName: "BitcoinEnv", dict: dict) { saved in
//                                //            guard saved else {
//                                //                return
//                                //            }
//                                // download SHA256SUMS
//                                // run script to verify sigs, install
//                                
//                            
                        }
                    }
                }
                task.resume()
                
            } else {
                print("not ready")
            }
        }
    }
}
