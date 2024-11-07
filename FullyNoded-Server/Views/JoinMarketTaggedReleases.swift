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
        self.existingVersion = existingVersion
        self.taggedRelease = taggedReleases[0]
    }
    
    var body: some View {
        if startCheckingForJoinMarketInstall, let tagName = taggedRelease.tagName {
            EmptyView()
                .onReceive(timerForJoinMarketInstall) { _ in
                    let jmwalletdPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName.replacingOccurrences(of: "v", with: ""))/scripts/jmwalletd.py"
                    let jmConfigPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
                    if fileExists(path: jmConfigPath), fileExists(path: jmwalletdPath) {
                        configureJm()
                    } else {
                        startCheckingForJoinMarketInstall = true
                    }
                }
        }
        
        if isAnimating, let tagName = taggedRelease.tagName {
            HStack() {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Installing and configuring Join Market \(tagName). (wait for the terminal script to complete)")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding([.leading, .top])
            
            Spacer()
        } else {
            if !joinMarketInstallComplete {
                Picker("Select a Join Market version to install:", selection: $taggedRelease) {
                    Text("Select a release").tag(UUID())
                    ForEach(taggedReleases, id: \.self) {
                        Text($0.tagName ?? "")
                            .tag(Optional($0.uuid))
                    }
                }
                .padding([.top, .leading, .trailing, .bottom])
                
                if let author = taggedRelease.author, let login = author.login, let tagName = taggedRelease.tagName {
                    Text("Join Market \(tagName), written by \(login).")
                        .padding([.leading, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                                   
                    Text(verbatim: "Downloading from \(taggedRelease.tarballURL ?? "")")
                        .padding([.leading, .bottom])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(verbatim: taggedRelease.name ?? "")
                                        .padding([.leading, .bottom])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(verbatim: taggedRelease.body ?? "")
                                        .padding([.leading, .bottom])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                                    HStack() {
                                        let url = "https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/release-notes/release-notes-\(tagName.replacingOccurrences(of: "v", with: "")).md"
                    
                                        Link("Release Notes", destination: URL(string: url)!)
                                    }
                                    .padding([.leading, .bottom])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button {
                        startCheckingForJoinMarketInstall = true
                        download(taggedRelease, useTor: false)
                    } label: {
                        Text("Install Join Market \(tagName)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    
                    Text(description)
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
    }
    
    
    private func configureJm() {
        print("configureJm")
        var chain = UserDefaults.standard.object(forKey: "chain") as? String ?? "signet"
        let port = UserDefaults.standard.object(forKey: "port") as? String ?? "38332"
        switch chain {
        case "main": chain = "mainnet"
        case "regtest": chain = "testnet"
        case "test": chain = "testnet"
        default:
            break
        }
        updateConf(key: "network", value: chain)
        updateConf(key: "rpc_port", value: port)
        updateConf(key: "rpc_wallet_file", value: "jm_wallet")
        
        DataManager.retrieve(entityName: "BitcoinRPCCreds") { rpcCreds in
            guard let rpcCreds = rpcCreds, 
                    let encryptedPassword = rpcCreds["password"] as? Data,
                    let decryptedPass = Crypto.decrypt(encryptedPassword),
                  let stringPass = String(data: decryptedPass, encoding: .utf8) else {
                showMessage(message: "Unable to get rpc creds to congifure JM.")
                return
            }
            
            updateConf(key: "rpc_password", value: stringPass)
            updateConf(key: "rpc_user", value: "FullyNoded-Server")
            
            BitcoinRPC.shared.command(method: "createwallet", params: ["wallet_name": "jm_wallet", "descriptors": false]) { (result, error) in
                guard error == nil else {
                    if !error!.contains("Database already exists.") {
                        showMessage(message: error!)
                    }
                    joinMarketInstallComplete = true
                    startCheckingForJoinMarketInstall = false
                    isAnimating = false
                    return
                }
                
                showMessage(message: "Join Market installed and configured ✓")
                joinMarketInstallComplete = true
                startCheckingForJoinMarketInstall = false
                isAnimating = false
            }
        }
    }
    
    private func updateConf(key: String, value: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        guard fileExists(path: jmConfPath) else { return }
        guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)) else {
            showMessage(message: "No Join Market conf.")
            return
        }
        guard let string = String(data: conf, encoding: .utf8) else {
            showMessage(message: "Can not convert JM config data to string.")
            return
        }
        let arr = string.split(separator: "\n")
        for item in arr {
            if item.hasPrefix("\(key) =") {
                let newConf = string.replacingOccurrences(of: item, with: key + " = " + value)
                if (try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)) == nil {
                    showMessage(message: "Failed writing to JM config.")
                }
            }
        }
    }
    
    private func showMessage(message: String) {
        isAnimating = false
        showError = true
        self.message = message
    }
    
    private func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
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
        
        downloadTask(url: tarballUrl) { data in
            guard let data = data else { return }
            let dirPath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket")
            if !fileExists(path: "/Users/\(NSUserName())/.fullynoded/JoinMarket") {
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
    }
    
    func downloadPublicKey(url: URL, tagName: String, author: String) {
        var pubkeyUrlRoot = "https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/refs/heads/master/pubkeys/"
        if author == "kristapsk" {
            pubkeyUrlRoot += "KristapsKaupe.asc"
        } else if author == "AdamISZ" {
            pubkeyUrlRoot += "AdamGibson.asc"
        }
        guard let pubKeyUrl = URL(string: pubkeyUrlRoot) else { return }
        downloadTask(url: pubKeyUrl) { data in
            guard let data = data else {
                return
            }
            let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/\(author).asc")
            guard ((try? data.write(to: filePath)) != nil) else {
                showMessage(message: "Writing file failed.")
                return
            }
            fetchAssets(url: url, tagName: tagName, author: author)
        }
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
    
    private func downloadTask(url: URL, completion: @escaping (Data?) -> Void) {
        let request = URLRequest(url: url)
        let task = URLSession.shared.downloadTask(with: request) { localURL, urlResponse, error in
            guard error == nil else {
                showMessage(message: error!.localizedDescription)
                completion(nil)
                return
            }
            guard let localURL = localURL else {
                showMessage(message: "Downloading \(url) failed.")
                completion(nil)
                return
            }
            guard let data = try? Data(contentsOf: localURL) else {
                showMessage(message: "No data in local url.")
                completion(nil)
                return
            }
            completion((data))
        }
        task.resume()
    }
    
    
    func downloadTarBallSig(url: URL, tagName: String, author: String) {
        downloadTask(url: url) { data in
            guard let data = data else {
                return
            }
            let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName).tar.gz.asc")
            guard ((try? data.write(to: filePath)) != nil) else {
                showMessage(message: "Unable to write file: Users/\(NSUserName())/.fullynoded/JoinMarket/joinmarket-\(tagName).tar.gz.asc")
                return
            }
            runScript(script: .launchJMInstaller, env: ["TAG_NAME": tagName, "AUTHOR": author])
            UserDefaults.standard.setValue(tagName, forKey: "tagName")
        }
    }
    
    func runScript(script: SCRIPT, env: [String: String]) {
        let taskQueue = DispatchQueue.global(qos: .background)
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

