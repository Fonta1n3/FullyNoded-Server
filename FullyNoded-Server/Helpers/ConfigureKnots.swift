//
//  ConfigureKnots.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 5/21/25.
//

import Foundation

class ConfigureKnots {
    
    class func checkForExistingConf(updatedPruneValue: Int?, completion: @escaping (Bool) -> Void) {
        var existingPruneValue: Int?
        KnotsConf.getKnotsConf { (conf, error) in
            if let existingKnotsConf = conf {
                var createBdbExists = false
                
                func setNow() {
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
                        if UserDefaults.standard.object(forKey: "knotsPort") == nil {
                            UserDefaults.standard.set("8662", forKey: "knotsPort")
                        }
                        
                        var updatedKnotsConf = existingKnotsConf.joined(separator: "\n")
                        if !createBdbExists {
                            // For Join Market to work...
                            updatedKnotsConf = "deprecatedrpc=create_bdb" + "\n" + updatedKnotsConf
                            if let updatedPruneValue = updatedPruneValue, let existingPruneValue = existingPruneValue {
                                updatedKnotsConf = updatedKnotsConf.replacingOccurrences(of: "prune=\(existingPruneValue)", with: "prune=\(updatedPruneValue)")
                            }
                        }
                        updatedKnotsConf = rpcauth + "\n" + updatedKnotsConf
                        setKnotsConf(updatedKnotsConf, completion: completion)
                    }
                }
                // check if deprecatedrpc=create_bdb exists, if not add it.
                for (i, item) in existingKnotsConf.enumerated() {
                    let arr = item.split(separator: "=")
                    if arr.count > 1 {
                        if let value = Int(arr[1])  {
                            if item.hasPrefix("prune=") {
                                if let updatedPruneValue = updatedPruneValue {
                                    UserDefaults.standard.setValue(updatedPruneValue, forKey: "prune")
                                    existingPruneValue = value
                                }
                            }
                            if item.hasPrefix("txindex=") {
                                UserDefaults.standard.setValue(value, forKey: "txindex")
                            }
                            
                        } else {
                            // deprecatedrpc=create_bdb
                            if item.contains("deprecatedrpc=create_bdb") {
                                createBdbExists = true
                            }
                        }
                    }
                    if i + 1 == existingKnotsConf.count {
                        setNow()
                    }
                }
                
                
            } else {
                if let defaultConf = KnotsConf.new() {
                    self.setKnotsConf(defaultConf, completion: completion)
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
    
    class func setKnotsConf(_ knotsConf: String, completion: @escaping (Bool) -> Void) {
        if KnotsConf.setKnotsConf(knotsConf) {
            setFullyNodedDirectory(completion: completion)
        } else {
            completion((false))
        }
    }
    
    static let fnServerDir = "/Users/\(NSUserName())/.fullynoded"
    
    class func setFullyNodedDirectory(completion: @escaping (Bool) -> Void) {
        createDirectory(fnServerDir, completion: completion)
        if writeFile("\(fnServerDir)/fullynoded.log", "") {
            createBitcoinKnotsDirectory(completion: completion)
        } else {
            completion((false))
        }
    }
    
    class func createBitcoinKnotsDirectory(completion: @escaping (Bool) -> Void) {
        let path = "\(fnServerDir)/BitcoinKnots"
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
        DataManager.retrieve(entityName: .knotsRpcCreds) { existingCreds in
            if let _ = existingCreds {
                DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: .knotsRpcCreds) { updated in
                    UserDefaults.standard.set("FullyNoded-Server", forKey: "rpcuser")
                    completion(updated)
                }
            } else {
                DataManager.saveEntity(entityName: .knotsRpcCreds, dict: ["password": encryptedPass]) { saved in
                    UserDefaults.standard.set("FullyNoded-Server", forKey: "rpcuser")
                    completion(saved)
                }
            }
        }
    }
}
