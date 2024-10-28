//
//  TaggedReleasesView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/25/24.
//

import SwiftUI

struct TaggedReleasesView: View {
    
    let timerForBitcoinInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var bitcoinCoreInstallComplete = false
    @State private var startCheckingForBitcoinInstall = false
    @State private var description = ""
    @State private var isAnimating = false
    @State private var showError = false
    @State private var message = ""
    @State private var dataDir = Defaults.shared.dataDir
    @State private var txIndex = Defaults.shared.txindex
    @State private var taggedRelease: TaggedReleaseElement = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: 0, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
    
    let taggedReleases: TaggedReleases
    let existingVersion: String
    
    init(taggedReleases: TaggedReleases, existingVersion: String) {
        self.taggedReleases = taggedReleases
        self.taggedRelease = taggedReleases[0]
        self.existingVersion = existingVersion
    }
    
    var body: some View {
        if !bitcoinCoreInstallComplete {
            Picker("Select a Bitcoin Core version to install:", selection: $taggedRelease) {
                Text("Select a release").tag(UUID())
                ForEach(taggedReleases, id: \.self) {
                    Text($0.tagName ?? "")
                        .tag(Optional($0.uuid))
                }
            }
            .padding([.top, .leading, .trailing])
                        
            HStack() {
                Text("Data Directory:")
                Label(dataDir, systemImage: "")
                Button("Update") {
                    chooseDataDir()
                }
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Do not update the data directory unless you want to save your Bitcoin Core data in a custom location like an external hard drive.")
                .padding([.leading])
                .foregroundStyle(.secondary)
            
            HStack() {
                if txIndex == 0 {
                    Label("Pruned node", systemImage: "")
                    
                    
                    Button("Do not prune") {
                        UserDefaults.standard.setValue(1, forKey: "txindex")
                        UserDefaults.standard.setValue(0, forKey: "prune")
                        txIndex = 1
                    }
                } else {
                    Label("Full node", systemImage: "")
                    
                    Button("Prune") {
                        UserDefaults.standard.setValue(0, forKey: "txindex")
                        UserDefaults.standard.setValue(1000, forKey: "prune")
                        txIndex = 0
                    }
                }
            }
            .padding([.leading, .trailing])
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let author = taggedRelease.author, let login = author.login, let tagName = taggedRelease.tagName {
                let processedVersion = tagName.replacingOccurrences(of: "v", with: "")
                var arch = "arm64"
                Text("Written by \(login)")
                    .padding(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                #if arch(x86_64)
                        arch = "x86_64"
                #endif
                    }
                Text(verbatim: "Downloading from https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz")
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
                
                Text(description)
                    .padding([.leading, .trailing])
                
                if startCheckingForBitcoinInstall {
                    EmptyView()
                        .onReceive(timerForBitcoinInstall) { _ in
                            let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)/bin/bitcoind"
                            if FileManager.default.fileExists(atPath: tempPath) {
                                bitcoinCoreInstallComplete = true
                                // save new envValues! and update lightning config if it exists
                                let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
                                if FileManager.default.fileExists(atPath: lightningConfPath) {
                                    // get the config
                                    guard let conf = try? Data(contentsOf: URL(fileURLWithPath: lightningConfPath)),
                                            let string = String(data: conf, encoding: .utf8) else {
                                        return
                                    }
                                    let arr = string.split(separator: "\n")
                                    guard arr.count > 0  else { return }
                                    for item in arr {
                                        if item.hasSuffix("/bin/bitcoin-cli") {
                                            let existingCliPathArr = item.split(separator: "=")
                                            if existingCliPathArr.count == 2 {
                                                let existingCliPath = existingCliPathArr[1]
                                                let newPath = existingCliPath.replacingOccurrences(of: existingVersion, with: "bitcoin-\(processedVersion)")
                                                let newConf = string.replacingOccurrences(of: existingCliPath, with: newPath)
                                                try? newConf.write(to: URL(fileURLWithPath: lightningConfPath), atomically: false, encoding: .utf8)
                                            }
                                        }
                                    }
                                }
                                saveEnvVaules(version: processedVersion)
                                startCheckingForBitcoinInstall = false
                            } else {
                                startCheckingForBitcoinInstall = true
                            }
                        }
                }
            }
        } else {
            Text("Bitcoin Core installed ✓")
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
    
    private func chooseDataDir() {
        let folderChooserPoint = CGPoint(x: 0, y: 0)
                let folderChooserSize = CGSize(width: 500, height: 600)
                let folderChooserRectangle = CGRect(origin: folderChooserPoint, size: folderChooserSize)
                let folderPicker = NSOpenPanel(contentRect: folderChooserRectangle, styleMask: .utilityWindow, backing: .buffered, defer: true)
                
                folderPicker.canChooseDirectories = true
                folderPicker.canChooseFiles = true
                folderPicker.allowsMultipleSelection = true
                folderPicker.canDownloadUbiquitousContents = true
                folderPicker.canResolveUbiquitousConflicts = true
                
                folderPicker.begin { response in
                    
                    if response == .OK {
                        let pickedFolder = folderPicker.urls[0].path().replacingOccurrences(of: "%20", with: " ")
                        UserDefaults.standard.setValue("\(pickedFolder.dropLast())", forKey: "dataDir")
                        self.dataDir = "\(pickedFolder.dropLast())"
                        updateCLNConfig(key: "bitcoin-datadir=")
                    }
                }
    }
    
    private func saveEnvVaules(version: String) {
        DataManager.deleteAllData(entityName: "BitcoinEnv") { deleted in
            guard deleted else { return }
            
            let dict = [
                "binaryName": "bitcoin-\(version)-arm64-apple-darwin.tar.gz",
                "version": version,
                "prefix": "bitcoin-\(version)",
                "dataDir": Defaults.shared.dataDir,
                "chain": Defaults.shared.chain
            ]
            
            DataManager.saveEntity(entityName: "BitcoinEnv", dict: dict) { saved in
                guard saved else {
                    showMessage(message: "Unable to save default bitcoin env values.")
                    return
                }
                bitcoinCoreInstallComplete = true
            }
        }
    }
    
    private func showMessage(message: String) {
        showError = true
        self.message = message
    }
    
    private func writeData(data: Data?, filePath: String) -> Bool {
        guard let data = data else { return false }
        let filePath = URL(fileURLWithPath: filePath)
        return ((try? data.write(to: filePath)) != nil)
    }
    
    private func downloadSHA256SUMS(processedVersion: String, arch: String) {
        let urlSHA256SUMS = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS"
        description = "Downloading SHA256SUMS file from \(urlSHA256SUMS)"
        downloadTask(url: URL(string: urlSHA256SUMS)!) { data in
            guard writeData(data: data, filePath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/SHA256SUMS") else { return }
            downloadSigs(processedVersion: processedVersion, arch: arch)
        }
    }
    
    private func downloadSigs(processedVersion: String, arch: String) {
        let urlSigs = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
        description = "Downloading the signed SHA256SUMS file from \(urlSigs)"
        downloadTask(url: URL(string: urlSigs)!) { data in
            guard writeData(data: data, filePath: "/Users/\(NSUserName())/.fullynoded/BitcoinCore/SHA256SUMS.asc") else { return }
            let binaryName  = "bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
            let binaryPrefix = "bitcoin-\(processedVersion)"
            installNow(binaryName: binaryName, version: processedVersion, prefix: binaryPrefix)
            startCheckingForBitcoinInstall = true
        }
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
        description = "Downloading Bitcoin Core tarball from \(macOSUrl)"
        CreateFNDirConfigureCore.checkForExistingConf { startDownload in
            if startDownload {
                isAnimating = true
                downloadTask(url: URL(string: macOSUrl)!) { data in
                    guard writeData(data: data, filePath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz") else { return }
                    downloadSHA256SUMS(processedVersion: processedVersion, arch: arch)
                }
            }
        }
    }
    
    private func downloadTask(url: URL, completion: @escaping (Data?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, urlResponse, error in
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
    
    private func updateCLNConfig(key: String) {
        // key = "bitcoin-datadir="
        let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
        guard let conf = conf(stringPath: lightningConfPath) else { return }
        let arr = conf.split(separator: "\n")
        for item in arr {
            if item.hasPrefix(key) {
                if key.hasPrefix("bitcoin-datadir") {
                    writeConf(conf: conf, key: key, value: Defaults.shared.dataDir, lightningConfPath: lightningConfPath, itemToReplace: item)
                } else if key.hasPrefix("bitcoin-rpcpassword") {
                    DataManager.retrieve(entityName: "BitcoinRPCCreds") { creds in
                        guard let creds = creds else { return }
                        guard let encryptedPass = creds["password"] as? Data else { return }
                        guard let decryptedPass = Crypto.decrypt(encryptedPass) else { return }
                        guard let rpcPass = String(data: decryptedPass, encoding: .utf8) else { return }
                        writeConf(conf: conf, key: key, value: rpcPass, lightningConfPath: lightningConfPath, itemToReplace: item)
                    }
                }
                
            }
        }
    }
    
    private func writeConf(conf: String, key: String, value: String, lightningConfPath: String, itemToReplace: Substring) {
        let newConf = conf.replacingOccurrences(of: itemToReplace, with: key + value)
        try? newConf.write(to: URL(fileURLWithPath: lightningConfPath), atomically: false, encoding: .utf8)
    }
    
    func installNow(binaryName: String, version: String, prefix: String) {
        let env = ["BINARY_NAME":binaryName, "VERSION":version]
        let ud = UserDefaults.standard
        ud.set(prefix, forKey: "binaryPrefix")
        ud.set(binaryName, forKey: "macosBinary")
        ud.set(version, forKey: "version")
        description = "Launching terminal to run a script to check the provided sha256sums against our own, verifying gpg sigs and unpack the tarball. "
        isAnimating = false
        updateCLNConfig(key: "bitcoin-rpcpassword=")
        runScript(script: .launchInstaller, env: env)
    }
    
    private func runScript(script: SCRIPT, env: [String: String]) {
        #if DEBUG
        print("run script: \(script.stringValue)")
        #endif
        
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
            let data = stdOut.fileHandleForReading.readDataToEndOfFile()
            let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
            var result = ""
            
            if let output = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("output: \(output)")
                #endif
                result += output
            }
            
            if let errorOutput = String(data: errData, encoding: .utf8) {
                #if DEBUG
                print("error: \(errorOutput)")
                #endif
                result += errorOutput
                if errorOutput != "" {
                    showMessage(message: errorOutput)
                }
            }
        }
    }
}
