//
//  InstallBtcCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

class CreateFNDirConfigureCore {
    
    class func checkForExistingConf(completion: @escaping (Bool) -> Void) {
        BitcoinConf.getBitcoinConf { (conf, error) in
            if let existingBitcoinConf = conf {
                for item in existingBitcoinConf {
                    let arr = item.split(separator: "=")
                    let value = arr[1]
                    if item.hasPrefix("prune=") {
                        UserDefaults.standard.setValue(Int(value), forKey: "prune")
                    }
                    if item.hasPrefix("txindex=") {
                        UserDefaults.standard.setValue(Int(value), forKey: "txindex")
                    }
                }
                let rpcuser = "FullyNoded-Server"
                guard let rpcAuthCreds = RPCAuth().generateCreds(username: rpcuser, password: nil) else {
                    completion(false)
                    print("unable to generate rpc auth creds.")
                    return
                }
                let rpcauth = rpcAuthCreds.rpcAuth
                let data = Data(rpcAuthCreds.rpcPassword.utf8)
                
                guard let encryptedPass = Crypto.encrypt(data) else {
                    #if DEBUG
                    print("Unable to encrypt rpc pass.")
                    #endif
                    completion(false)
                    return
                }
                updateRpcCreds(encryptedPass: encryptedPass, rpcUser: rpcuser) { updated in
                    guard updated else {
                        #if DEBUG
                        print("Unable to save new password.")
                        #endif
                        completion(false)
                        return
                    }
                    
                    var updatedBitcoinConf = existingBitcoinConf.joined(separator: "\n")
                    updatedBitcoinConf = rpcauth + "\n" + updatedBitcoinConf
                    setBitcoinConf(updatedBitcoinConf, completion: completion)
                }
                
            } else {
                if let defaultConf = BitcoinConf.newBitcoinConf() {
                    self.setBitcoinConf(defaultConf, completion: completion)
                } else {
                    #if DEBUG
                    print("Error fetching bitcoin.conf: \(error).")
                    #endif
                    completion(false)
                }
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
        guard let file = fileContents.data(using: .utf8) else { return false }
        return ((try? file.write(to: filePath)) != nil)
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
    
    class func updateRpcCreds(encryptedPass: Data, rpcUser: String, completion: @escaping (Bool) -> Void) {
        DataManager.retrieve(entityName: "BitcoinRPCCreds") { existingCreds in
            if let _ = existingCreds {
                DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: "BitcoinRPCCreds") { updated in
                    completion(updated)
                }
            } else {
                DataManager.saveEntity(entityName: "BitcoinRPCCreds", dict: ["password": encryptedPass]) { saved in
                    completion(saved)
                }
            }
        }
    }
}
