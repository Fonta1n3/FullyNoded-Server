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
                
                if startCheckingForBitcoinInstall {
                    EmptyView()
                        .onReceive(timerForBitcoinInstall) { _ in
                            let tempPath = "/Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)/bin/bitcoind"
                            if FileManager.default.fileExists(atPath: tempPath) {
                                //showMessage(message: "Bitcoin Core install completed ✓")
                                bitcoinCoreInstallComplete = true
                                
                                // save new envValues! and update lightning config if it exists
                                let lightningConfPath = "/Users/\(NSUserName())/.lightning/config"
                                if FileManager.default.fileExists(atPath: lightningConfPath) {
                                    // get the config
                                    
                                    guard let conf = try? Data(contentsOf: URL(fileURLWithPath: lightningConfPath)),
                                            let string = String(data: conf, encoding: .utf8) else {
                                        print("no conf")
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
    
    private func saveEnvVaules(version: String) {
        DataManager.deleteAllData(entityName: "BitcoinEnv") { deleted in
            guard deleted else { return }
            
            let dict = [
                "binaryName": "bitcoin-\(version)-arm64-apple-darwin.tar.gz",
                "version": version,
                "prefix": "bitcoin-\(version)",
                "dataDir": "/Users/\(NSUserName())/Library/Application Support/Bitcoin",
                "chain": UserDefaults.standard.string(forKey: "chain") ?? "signet"
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
    
    private func downloadSHA256SUMS(processedVersion: String, arch: String) {
        let urlSHA256SUMS = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS"
        description = "Downloading SHA256SUMS file from \(urlSHA256SUMS)"
        let task = URLSession.shared.downloadTask(with: URL(string: urlSHA256SUMS)!) { localURL, urlResponse, error in
            if let localURL = localURL {
                if let data = try? Data(contentsOf: localURL) {
                    print(localURL)
                    let filePath = URL(fileURLWithPath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/SHA256SUMS")
                    guard ((try? data.write(to: filePath)) != nil) else {
                        return
                    }
                    downloadSigs(processedVersion: processedVersion, arch: arch)
                }
            }
        }
        task.resume()
    }
    
    private func downloadSigs(processedVersion: String, arch: String) {
        let urlSigs = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
        description = "Downloading th signed SHA256SUMS file from \(urlSigs)"
        let task = URLSession.shared.downloadTask(with: URL(string: urlSigs)!) { localURL, urlResponse, error in
            isAnimating = false
            if let localURL = localURL {
                if let data = try? Data(contentsOf: localURL) {
                    let filePath = URL(fileURLWithPath: "/Users/\(NSUserName())/.fullynoded/BitcoinCore/SHA256SUMS.asc")
                    guard ((try? data.write(to: filePath)) != nil) else {
                        return
                    }
                    let binaryName  = "bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
                    let macosURL = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
                    let shaURL = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS"
                    let binaryPrefix = "bitcoin-\(processedVersion)"
                    let shasumsSignedUrl = "https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
                    installNow(binaryName: binaryName, macosURL: macosURL, shaURL: shaURL, version: processedVersion, prefix: binaryPrefix, sigsUrl: shasumsSignedUrl)
                    startCheckingForBitcoinInstall = true
                }
            }
        }
        task.resume()
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
        InstallBitcoinCore.checkExistingConf { ready in
            if ready {
                isAnimating = true
                let task = URLSession.shared.downloadTask(with: URL(string: macOSUrl)!) { localURL, urlResponse, error in
                    if let localURL = localURL {
                        if let data = try? Data(contentsOf: localURL) {
                            print(localURL)
                            let filePath = URL(fileURLWithPath: "Users/\(NSUserName())/.fullynoded/BitcoinCore/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz")
                            guard ((try? data.write(to: filePath)) != nil) else {
                                return
                            }
                            downloadSHA256SUMS(processedVersion: processedVersion, arch: arch)
                        }
                    }
                }
                task.resume()
            }
        }
    }
    
        func installNow(binaryName: String, macosURL: String, shaURL: String, version: String, prefix: String, sigsUrl: String) {
            let env = ["BINARY_NAME":binaryName, "MACOS_URL":macosURL, "SHA_URL":shaURL, "VERSION":version, "PREFIX":prefix, "SIGS_URL": sigsUrl]
            let ud = UserDefaults.standard
            ud.set(prefix, forKey: "binaryPrefix")
            ud.set(binaryName, forKey: "macosBinary")
            ud.set(version, forKey: "version")
            description = "Launching terminal to run a script to check the provided sha256sums against our own, verifying gpg sigs and unpack the tarball. "
            isAnimating = false
            runScript(script: .launchInstaller, env: env)
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
    
    private func checkForBitcoinCore(script: SCRIPT, env: [String: String]) {
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
