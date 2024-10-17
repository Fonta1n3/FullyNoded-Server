//
//  JoinMarketTaggedReleases.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/11/24.
//

import SwiftUI

struct JoinMarketTaggedReleasesView: View {
    
    let timerForJoinMarketInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var joinMarketInstallComplete = false
    @State private var startCheckingForJoinMarketInstall = false
    @State private var description = ""
    @State private var isAnimating = false
    @State private var showError = false
    @State private var message = ""
    @State private var taggedRelease: TaggedReleaseElement = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: 0, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
    
    let taggedReleases: TaggedReleases
    let existingVersion: String
    
    init(taggedReleases: TaggedReleases, existingVersion: String) {
        self.taggedReleases = taggedReleases
        self.taggedRelease = taggedReleases[0]
        self.existingVersion = existingVersion
    }
    
    var body: some View {
        if !joinMarketInstallComplete {
            Picker("Select a Join Market version to install:", selection: $taggedRelease) {
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
                
                               
                Text(verbatim: "Downloading from \(taggedRelease.tarballURL ?? "")")
                                    .padding(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(verbatim: taggedRelease.name ?? "")
                                    .padding(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(verbatim: taggedRelease.body ?? "")
                                    .padding(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
//
                                HStack() {
                                    let url = "https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/release-notes/release-notes-\(tagName.replacingOccurrences(of: "v", with: "")).md"
                
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
                        startCheckingForJoinMarketInstall = true
                        download(taggedRelease, useTor: false)
                    } label: {
                        Text("Install Join Market \(tagName)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                
                Text(description)
                
                if startCheckingForJoinMarketInstall {
                    EmptyView()
                        .onReceive(timerForJoinMarketInstall) { _ in
                            print("onReceive: timerForJoinMarketInstall")
                            let tempPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName.replacingOccurrences(of: "v", with: ""))/scripts/jmwalletd.py"
                            if FileManager.default.fileExists(atPath: tempPath) {
                                showMessage(message: "Join Market install completed ✓")
                                joinMarketInstallComplete = true
                                startCheckingForJoinMarketInstall = false
                                isAnimating = false
                            } else {
                                startCheckingForJoinMarketInstall = true
                            }
                        }
                }
            }
        } else {
            Text("Join Market installed ✓")
                .padding(.all)
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
        isAnimating = false
        showError = true
        self.message = message
    }
    
    private func download(_ taggedRelease: TaggedReleaseElement, useTor: Bool) {
        isAnimating = true
        guard var tagName = taggedRelease.tagName else {
            showMessage(message: "No tag name.")
            return
        }
        tagName = tagName.replacingOccurrences(of: "v", with: "")
        
        guard let tarballUrlCheck = taggedRelease.tarballURL else {
            showMessage(message: "No tarball url.")
            return
        }
        
        guard let tarballUrl = URL(string: tarballUrlCheck) else {
            showMessage(message: "Failed converting to taball url string to url.")
            return
        }
        
        let task = URLSession.shared.downloadTask(with: tarballUrl) { localURL, urlResponse, error in
            guard error == nil else {
                showMessage(message: error!.localizedDescription)
                return
            }
            
            guard let localURL = localURL else {
                showMessage(message: "No local url.")
                return
            }
            
            guard let data = try? Data(contentsOf: localURL) else {
                showMessage(message: "No data in local url.")
                return
            }
            
            let dirPath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket")
            if !FileManager.default.fileExists(atPath: dirPath.path()) {
                do {
                    try FileManager.default.createDirectory(atPath: dirPath.path(), withIntermediateDirectories: true, attributes: nil)
                } catch {
                    showMessage(message: error.localizedDescription)
                }
            }
            
            let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName).tar.gz")
            guard ((try? data.write(to: filePath)) != nil) else {
                showMessage(message: "Writing file failed.")
                return
            }
            
            guard let assetsURLCheck = taggedRelease.assetsURL, let assetsUrl = URL(string: assetsURLCheck), let author = taggedRelease.author, let authorName = author.login else {
                showMessage(message: "No assets url.")
                return
            }
            
            downloadPublicKey(url: assetsUrl, tagName: tagName, author: authorName)
        }
        
        task.resume()
    }
    
    func downloadPublicKey(url: URL, tagName: String, author: String) {
        var pubkeyUrlRoot = "https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/refs/heads/master/pubkeys/"
        if author == "kristapsk" {
            pubkeyUrlRoot += "KristapsKaupe.asc"
        } else if author == "AdamISZ" {
            pubkeyUrlRoot += "AdamGibson.asc"
        }
        guard let pubKeyUrl = URL(string: pubkeyUrlRoot) else { return }
        let task = URLSession.shared.downloadTask(with: pubKeyUrl) { localURL, urlResponse, error in
            guard error == nil else {
                showMessage(message: error!.localizedDescription)
                return
            }
            guard let localURL = localURL else {
                showMessage(message: "No local url.")
                return
            }
            guard let data = try? Data(contentsOf: localURL) else {
                showMessage(message: "No data in local url.")
                return
            }
            
            let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/\(author).asc")
            
            guard ((try? data.write(to: filePath)) != nil) else {
                showMessage(message: "Writing file failed.")
                return
            }
            
            fetchAssets(url: url, tagName: tagName, author: author)
        }
        task.resume()
    }
    
    func fetchAssets(url: URL, tagName: String, author: String) {
        let request = URLRequest(url: url)
        let session = URLSession.shared
        
        let task = session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                showMessage(message: error!.localizedDescription)
                return
            }
            
            guard let data = data else {
                showMessage(message: "No data.")
                return
            }
            
            guard let assets = try? JSONDecoder().decode(Assets.self, from: data) else {
                showMessage(message: "Error encoding to assets.")
                return
            }
            
            for asset in assets {
                guard let name = asset.name, let sigUrlCheck = asset.url else {
                    showMessage(message: "No asset name or url.")
                    return
                }
                
                if name.hasSuffix(".tar.gz.asc") {
                    guard let sigUrl = URL(string: sigUrlCheck) else {
                        showMessage(message: "Unable to convert sig url string to url.")
                        return
                    }
                    downloadTarBallSig(url: sigUrl, tagName: tagName, author: author)
                }
            }
        }
        task.resume()
    }
    
    
    func downloadTarBallSig(url: URL, tagName: String, author: String) {
        var request = URLRequest(url: url)
        request.addValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let task = URLSession.shared.downloadTask(with: request) { localURL, urlResponse, error in
            if let localURL = localURL {
                if let data = try? Data(contentsOf: localURL) {
                    
                    let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName).tar.gz.asc")
                    guard ((try? data.write(to: filePath)) != nil) else {
                        print("writing file failed")
                        return
                    }
                    print("sig saved to .fullynoded...")
                    
                    // Now we can run install script.
                    runScript(script: .launchJMInstaller, env: ["TAG_NAME": tagName, "AUTHOR": author])
                    UserDefaults.standard.setValue(tagName, forKey: "tagName")
                }
            }
        }
        task.resume()
    }
    
    func runScript(script: SCRIPT, env: [String:String]) {
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            let resource = script.stringValue
            guard let path = Bundle.main.path(forResource: resource, ofType: "command") else { return }
            let stdOut = Pipe()
            let stdErr = Pipe()
            let task = Process()
            task.launchPath = path
            task.environment = env
            task.standardOutput = stdOut
            task.standardError = stdErr
            task.launch()
            task.waitUntilExit()
        }
    }
    
}

