//
//  InstallBtcCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

class InstallBitcoinCore {
    class func checkExistingConf() {
        var proxyExists = false
        var onlynetExists = false
        var discoverExists = false
        var listenExists = false
        //var externalIpExists = false
        var fullynodedServerUserExists = false
        
        BitcoinConf.getBitcoinConf { (conf, error) in
            guard let conf = conf, !error, conf.count > 0 else {
                if let defaultConf = BitcoinConf.bitcoinConf() {
                    self.setBitcoinConf(defaultConf)
                } else {
//                    simpleAlert(message: "Something went wrong...", info: "Unable to create the default bitcoin.conf, please let us know about this bug.", buttonLabel: "OK")
                }
                return
            }
            
            var rpcauth = "#rpcauth="
            let rpcuser = "FullyNoded-Server"
            guard let rpcAuthCreds = RPCAuth().generateCreds(username: rpcuser, password: nil) else { return }
            rpcauth = rpcAuthCreds.rpcAuth
            //UserDefaults.standard.setValue(rpcAuthCreds.rpcPassword, forKey: "rpcpassword")
            let data = Data(rpcAuthCreds.rpcPassword.utf8)
            
            guard let encryptedPass = Crypto.encrypt(data) else {
                print("unable to encrypt rpc pass.")
                return
            }
            
            DataManager.saveEntity(entityName: "BitcoinRPCCreds", dict: ["password": encryptedPass]) { saved in
                guard saved else { return }
                
                UserDefaults.standard.setValue(rpcuser, forKey: "rpcuser")
                
                var updatedConf = conf
                
                for (i, setting) in conf.enumerated() {
                    if setting.contains("=") {
                        let arr = setting.components(separatedBy: "=")
                        let k = arr[0]
                        let existingValue = arr[1]
                        
                        switch k {
                        case "rpcauth":
                            if existingValue.hasPrefix("\(rpcuser):") {
                                fullynodedServerUserExists = true
                                updatedConf[i] = rpcauth
                            }
                            
    //                    case "rpcwhitelist":
    //                        if existingValue.hasPrefix("\(rpcuser):") {
    //                            fullynodedServerWhitelistExists = true
    //                        }
                            
                        case "onlynet", "#onlynet":
                            onlynetExists = true
                            
//                        case "externalip":
//                            externalIpExists = true
                            
                        case "discover", "#discover":
                            discoverExists = true
                            
                        case "blocksdir":
                            UserDefaults.standard.setValue(existingValue, forKey: "blockDir")
                            
                        case "testnet", "regtest", "signet":
                            if existingValue != "" {
    //                            simpleAlert(message: "Incompatible bitcoin.conf setting!", info: "GordianServer allows you to run multiple networks simultaneously, we do this by specifying which chain we want to launch as a command line argument. Specifying a network in your bitcoin.conf is not compatible with this approach, please remove the line in your conf file which specifies a network.", buttonLabel: "OK")
                            }
                            
                        case "proxy", "#proxy":
                            proxyExists = true
                            
                        case "listen", "#listen":
                            listenExists = true
                            
                        default:
                            break
                        }
                    }
                }
                
                var bitcoinConf = updatedConf.joined(separator: "\n")
                
                if !fullynodedServerUserExists {
                    bitcoinConf = rpcauth + "\n" + bitcoinConf
                }
                
    //            if !fullynodedServerWhitelistExists {
    //                bitcoinConf = "rpcwhitelist=\(rpcuser):\(rpcWhiteList)\n" + bitcoinConf
    //            }
                
                if !proxyExists {
                    bitcoinConf = "proxy=127.0.0.1:19050\n" + bitcoinConf
                }
                
                if !listenExists {
                    bitcoinConf = "listen=1\n" + bitcoinConf
                }
                
                if !discoverExists {
                    bitcoinConf = "discover=1\n" + bitcoinConf
                }
                
                if !onlynetExists {
                    bitcoinConf = "#onlynet=onion\n" + bitcoinConf
                }
                
//                if !externalIpExists {
//                    bitcoinConf = "externalip=\(TorClient.sharedInstance.p2pHostname(chain: "main") ?? "")\n" + bitcoinConf
//                }
                
                setBitcoinConf(bitcoinConf)
            }
        }
    }
    
    class func createDirectory(_ path: String) {
        let directory = URL(fileURLWithPath: path, isDirectory: true).path
        
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("\(path) previously created.")
        }
    }
    
    class func writeFile(_ path: String, _ fileContents: String) -> Bool {
        let filePath = URL(fileURLWithPath: path)
        
        guard let file = fileContents.data(using: .utf8) else {
            //simpleAlert(message: "There was an issue...", info: "Unable to convert the bitcoin.conf to data.", buttonLabel: "OK")
            return false
        }
        
        do {
            try file.write(to: filePath)
            return true
        } catch {
            return false
        }
    }
    
    class func setBitcoinConf(_ bitcoinConf: String) {
        if BitcoinConf.setBitcoinConf(bitcoinConf) {
            setFullyNodedDirectory()
        } else {
            //simpleAlert(message: "There was an issue...", info: "Unable to create the bitcoin.conf, please let us know about this bug.", buttonLabel: "OK")
        }
    }
    
    class func setFullyNodedDirectory() {
        createDirectory("/Users/\(NSUserName())/.fullynoded")
        
        if writeFile("/Users/\(NSUserName())/.fullynoded/fullynoded.log", "") {
            createBitcoinCoreDirectory()
        } else {
            //simpleAlert(message: "There was an issue...", info: "Unable to create the fullynoded.log, please let us know about this bug.", buttonLabel: "OK")
        }
    }
    
    class func createBitcoinCoreDirectory() {
        let path = "/Users/\(NSUserName())/.fullynoded/BitcoinCore"
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
            createDirectory(path)
            getURLs()
        } catch {
            //simpleAlert(message: "Something went wrong...", info: "When checking for the \(path) folder we got an error: \(error.localizedDescription)", buttonLabel: "OK")
        }
    }
    
    class func getURLs() {
        LatestBtcCoreRelease.get { (dict, error) in
            guard let dict = dict else {
                //simpleAlert(message: "Error", info: "There was an error fetching the latest Bitcoin Core version number and related URL's, please check your internet connection and try again: \(error ?? "unknown")", buttonLabel: "OK")
                return
            }
            
            let binaryName = dict["macosBinary"] as! String
            let macosURL = dict["macosURL"] as! String
            let shaURL = dict["shaURL"] as! String
            let version = dict["version"] as! String
            let prefix = dict["binaryPrefix"] as! String
            let signatures = dict["shasumsSignedUrl"] as! String
            
            self.standUp(binaryName: binaryName, macosURL: macosURL, shaURL: shaURL, version: version, prefix: prefix, sigsUrl: signatures)
        }
    }
    
    class func standUp(binaryName: String, macosURL: String, shaURL: String, version: String, prefix: String, sigsUrl: String) {
        let env = ["BINARY_NAME":binaryName, "MACOS_URL":macosURL, "SHA_URL":shaURL, "VERSION":version, "PREFIX":prefix, "SIGS_URL": sigsUrl]
        let ud = UserDefaults.standard
        ud.set(prefix, forKey: "binaryPrefix")
        ud.set(binaryName, forKey: "macosBinary")
        ud.set(version, forKey: "version")
        runScript(script: .launchInstaller, env: env)
    }
    
    class private func runScript(script: SCRIPT, env: [String:String]) {
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
