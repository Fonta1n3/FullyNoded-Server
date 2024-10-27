//
//  InstallBtcCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

class CreateFNDirConfigureCore {
    class func checkExistingConf(completion: @escaping (Bool) -> Void) {
        BitcoinConf.getBitcoinConf { (conf, error) in
            guard let conf = conf, !error, conf.count > 0 else {
                if let defaultConf = BitcoinConf.bitcoinConf() {
                    self.setBitcoinConf(defaultConf, completion: completion)
                } else {
                    #if DEBUG
                    print("Error fetching bitcoin.conf: \(error).")
                    #endif
                    completion(false)
                }
                return
            }
            
            let rpcuser = "FullyNoded-Server"
            guard let rpcAuthCreds = RPCAuth().generateCreds(username: rpcuser, password: nil) else { return }
            let rpcauth = rpcAuthCreds.rpcAuth
            let data = Data(rpcAuthCreds.rpcPassword.utf8)
            
            guard let encryptedPass = Crypto.encrypt(data) else {
                #if DEBUG
                print("Unable to encrypt rpc pass.")
                #endif
                completion(false)
                return
            }
            
            DataManager.saveEntity(entityName: "BitcoinRPCCreds", dict: ["password": encryptedPass]) { saved in
                guard saved else {
                    #if DEBUG
                    print("Unable to save new password.")
                    #endif
                    completion(false)
                    return
                }
                
                UserDefaults.standard.setValue(rpcuser, forKey: "rpcuser")
                var bitcoinConf = conf.joined(separator: "\n")
                bitcoinConf = rpcauth + "\n" + bitcoinConf
                setBitcoinConf(bitcoinConf, completion: completion)
            }
        }
    }
    
    class func createDirectory(_ path: String, completion: @escaping (Bool) -> Void) {
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
            return false
        }
        
        do {
            try file.write(to: filePath)
            return true
        } catch {
            return false
        }
    }
    
    class func setBitcoinConf(_ bitcoinConf: String, completion: @escaping (Bool) -> Void) {
        if BitcoinConf.setBitcoinConf(bitcoinConf) {
            setFullyNodedDirectory(completion: completion)
        } else {
            completion((false))
        }
    }
    
    class func setFullyNodedDirectory(completion: @escaping (Bool) -> Void) {
        createDirectory("/Users/\(NSUserName())/.fullynoded", completion: completion)
        
        if writeFile("/Users/\(NSUserName())/.fullynoded/fullynoded.log", "") {
            createBitcoinCoreDirectory(completion: completion)
        } else {
            completion((false))
        }
    }
    
    class func createBitcoinCoreDirectory(completion: @escaping (Bool) -> Void) {
        let path = "/Users/\(NSUserName())/.fullynoded/BitcoinCore"
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
            createDirectory(path, completion: completion)
            completion((true))
            
        } catch {
            completion((false))
        }
    }
}
