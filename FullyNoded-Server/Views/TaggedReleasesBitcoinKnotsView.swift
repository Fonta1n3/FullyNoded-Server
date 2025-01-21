//
//  TaggedReleasesBitcoinKnotsView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/21/25.
//

import SwiftUI

struct TaggedReleasesBitcoinKnotsView: View {
    
    let timerForInstall = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var fnServerPath = Defaults.shared.fnDataDir
    @State private var prune = false
    @State private var prunedAmount = ""
    @State private var installComplete = false
    @State private var startCheckingForInstall = false
    @State private var description = ""
    @State private var isAnimating = false
    @State private var showError = false
    @State private var message = ""
    @State private var bitcoinKnotsDataDir = Defaults.shared.bitcoinKnotsDataDir
    @State private var fnDataDirectory = Defaults.shared.fnDataDir
    @State private var txIndex = Defaults.shared.txindex
    @State private var taggedRelease: TaggedReleaseElement = .init(url: nil, assetsURL: nil, uploadURL: nil, htmlURL: nil, id: 0, author: nil, nodeID: nil, tagName: "", targetCommitish: nil, name: nil, draft: nil, prerelease: nil, createdAt: nil, publishedAt: nil, tarballURL: "", zipballURL: nil, body: nil)
    
    let taggedReleasesBitcoinKnots: TaggedReleases
    let existingVersion: String
    
    init(taggedReleasesBitcoinKnots: TaggedReleases, existingVersion: String) {
        self.taggedReleasesBitcoinKnots = taggedReleasesBitcoinKnots
        self.existingVersion = existingVersion
        self.taggedRelease = taggedReleasesBitcoinKnots[0]
    }
    
    var body: some View {
        if !installComplete {
            Picker("Select a Bitcoin Knots version to install:", selection: $taggedRelease) {
                Text("Select a release").tag(UUID())
                ForEach(taggedReleasesBitcoinKnots, id: \.self) {
                    Text($0.tagName ?? "")
                        .tag(Optional($0.uuid))
                }
            }
            .padding([.top, .leading, .trailing])
                        
            
            
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
                // Make 27x dynamic!
                // https://bitcoinknots.org/files/27.x/27.1.knots20240801/bitcoin-27.1.knots20240801-aarch64-linux-gnu-debug.tar.gz
                Text(verbatim: "Downloading from https://bitcoinknots.org/files/27x/\(tagName)-\(arch)-apple-darwin.tar.gz")
                    .padding(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack() {
                    let url = "https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-\(tagName.replacingOccurrences(of: "v", with: "")).md"
                    
                    Link("Release Notes", destination: URL(string: url)!)
                }
                .padding([.leading, .bottom])
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Label("Configuration options", systemImage: "gear")
                    .padding(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                                
                HStack() {
                    Text("Bitcoin Knots data directory:")
                    Label(bitcoinKnotsDataDir, systemImage: "")
                    Button("Update") {
                        chooseDataDir()
                    }
                }
                .padding([.leading, .trailing])
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Do not update the data directory unless you want to save your Bitcoin Knots data in a custom location like an external hard drive.")
                    .padding([.bottom, .leading])
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                
                
                HStack() {
                    Toggle("Prune", isOn: $prune)
                        .onChange(of: prune) { oldValue, newValue in
                            if newValue {
                                UserDefaults.standard.setValue(0, forKey: "txindex")
                                UserDefaults.standard.setValue(1000, forKey: "prune")
                                txIndex = 0
                                prunedAmount = "\(Double(Defaults.shared.prune) / 0.00104858)"
                            } else {
                                UserDefaults.standard.setValue(1, forKey: "txindex")
                                UserDefaults.standard.setValue(0, forKey: "prune")
                            }
                            
                        }
                    if prune {
                        TextField("", text: $prunedAmount)
                        
                    }
                }
                .padding([.leading, .trailing])
                .frame(maxWidth: .infinity, alignment: .leading)
                if prune {
                    Text("The amount in giga bytes the blockchain will consume.")
                        .foregroundStyle(.secondary)
                        .padding([.leading, .trailing])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack() {
                    if isAnimating {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    
                    Button {
                        install(taggedRelease, useTor: false)
                    } label: {
                        Text("Install Bitcoin Knots \(tagName)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                
                Text(description)
                    .padding([.leading, .trailing])
                
                if startCheckingForInstall {
                    EmptyView()
                        .onReceive(timerForInstall) { _ in
                            let tempPath = "\(fnServerPath)/BitcoinKnots/bitcoin-\(processedVersion)/bin/bitcoind"
                            if FileManager.default.fileExists(atPath: tempPath) {
                                installComplete = true
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
                                startCheckingForInstall = false
                            } else {
                                startCheckingForInstall = true
                            }
                        }
                }
            }
        } else {
            Text("Bitcoin Knots installed ✓")
                .padding(.all)
        }
        Spacer()
            .onAppear {
                prune = !((Defaults.shared.prune) == 0)
                if prune {
                    prunedAmount = "\((Double(Defaults.shared.prune) * 0.00104858).rounded(toPlaces: 1))"
                }
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
            guard response == .OK else { return }
            let pickedFolder = folderPicker.urls[0].path().replacingOccurrences(of: "%20", with: " ").dropLast()
            
                UserDefaults.standard.setValue("\(pickedFolder)", forKey: "dataDir")
                self.bitcoinKnotsDataDir = "\(pickedFolder)"
            
        }
    }
    
    private func saveEnvVaules(version: String) {
        DataManager.deleteAllData(entityName: .bitcoinEnv) { deleted in
            guard deleted else { return }
            
            let dict = [
                "binaryName": "bitcoin-\(version)-arm64-apple-darwin.tar.gz",
                "version": version,
                "prefix": "bitcoin-\(version)",
                "dataDir": Defaults.shared.bitcoinKnotsDataDir,
                "chain": Defaults.shared.chain
            ]
            
            DataManager.saveEntity(entityName: .bitcoinEnv, dict: dict) { saved in
                guard saved else {
                    showMessage(message: "Unable to save default bitcoin env values.")
                    return
                }
                installComplete = true
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
        let urlSHA256SUMS = "https://bitcoinKnots.org/bin/bitcoin-Knots-\(processedVersion)/SHA256SUMS"
        description = "Downloading SHA256SUMS file from \(urlSHA256SUMS)"
        downloadTask(url: URL(string: urlSHA256SUMS)!) { data in
            guard writeData(data: data, filePath: "\(fnServerPath)/BitcoinKnots/SHA256SUMS") else { return }
            downloadSigs(processedVersion: processedVersion, arch: arch)
        }
    }
    
    private func downloadSigs(processedVersion: String, arch: String) {
        let urlSigs = "https://bitcoinKnots.org/bin/bitcoin-Knots-\(processedVersion)/SHA256SUMS.asc"
        description = "Downloading the signed SHA256SUMS file from \(urlSigs)"
        downloadTask(url: URL(string: urlSigs)!) { data in
            guard writeData(data: data, filePath: "\(fnServerPath)/BitcoinKnots/SHA256SUMS.asc") else { return }
            let binaryName  = "bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
            let binaryPrefix = "bitcoin-\(processedVersion)"
            installNow(binaryName: binaryName, version: processedVersion, prefix: binaryPrefix)
            startCheckingForInstall = true
        }
    }
    
    private func install(_ taggedRelease: TaggedReleaseElement, useTor: Bool) {
        var newPruneAmount: Int?
        if prune, let dblAmount = Double(prunedAmount) {
            let mebibytes = Int(dblAmount * 953.674)
            UserDefaults.standard.setValue("\(mebibytes)", forKey: "prune")
            newPruneAmount = mebibytes
        }
        guard let tagName = taggedRelease.tagName else {
            showMessage(message: "No tagged name.")
            return
        }
        var processedVersion = tagName.replacingOccurrences(of: "v", with: "")
        let arr = processedVersion.split(separator: ".")
        var arch = "arm64"
        #if arch(x86_64)
        arch = "x86_64"
        #endif
        let root = "https://bitcoinknots.org/files/"
        let versionNumberInt = "\(arr[0])"
        let sha256sumsUrl = "\(root)\(versionNumberInt).x/\(processedVersion)/SHA256SUMS"
        print("sha256sumsUrl: \(sha256sumsUrl)")
        let sha256sumsSigUrl = "\(root)\(versionNumberInt).x/\(processedVersion)/SHA256SUMS.asc"
        print("sha256sumsSigUrl: \(sha256sumsSigUrl)")
        let macOsUrl = "https://bitcoinknots.org/files/\(versionNumberInt).x/\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
        print("macOsUrl: \(macOsUrl)")
        print("taggedName: \(tagName)")
        print("processedVersion: \(processedVersion)")
        
        
        
        let downloader = FileDownloader()
        let directoryPath = Defaults.shared.fnDataDir + "/BitcoinKnots"

        downloader.downloadAndSaveFile(toDirectory: directoryPath, fromURL: macOsUrl) { success, message in
            isAnimating = true
            if success {
                downloader.downloadAndSaveFile(toDirectory: directoryPath, fromURL: sha256sumsUrl) { success, message in
                    if success {
                        downloader.downloadAndSaveFile(toDirectory: directoryPath, fromURL: sha256sumsSigUrl) { success, message in
                            if success {
                                // checkSigs and hash
                                // configureKnots
                                // extract
                                print("now we check sigs next")
                                let filename = "bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
                                let tarballPath = directoryPath + "/" + filename
                                extract(tarballPath: tarballPath, binaryName: filename, version: processedVersion)
                            } else {
                                print("Error: \(message)") // Error message if failed
                            }
                        }
                    } else {
                        print("Error: \(message)") // Error message if failed
                    }
                }
            } else {
                print("Error: \(message)") // Error message if failed
            }
        }
        
        
        
//        // The onion for bitcoinKnots.org wasn't working for me... will try again. clearnet hardcoded for now.
//        let clearnet = "https://bitcoinKnots.org"
//        var macOSUrl = "\(onion)/bin/bitcoin-Knots-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
//        macOSUrl = "\(clearnet)/bin/bitcoin-Knots-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz"
//        description = "Downloading Bitcoin Knots tarball from \(macOSUrl)"
//        
//        CreateFNDirConfigureKnots.checkForExistingConf(updatedPruneValue: newPruneAmount) { startDownload in
//            print("startDownload")
//            if startDownload {
//                isAnimating = true
//                downloadTask(url: URL(string: macOSUrl)!) { data in
//                    guard writeData(data: data, filePath: "\(fnServerPath)/BitcoinKnots/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz") else { return }
//                    downloadSHA256SUMS(processedVersion: processedVersion, arch: arch)
//                }
//            }
//        }
    }
    
    private func extract(tarballPath: String, binaryName: String, version: String) {
        let env = ["BINARY_NAME": binaryName, "VERSION": version]
        ScriptUtil.runScript(script: .launchExtractKnots, env: env, args: nil) { (output, rawData, errorMessage) in
            print("launchExtractKnots")
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

