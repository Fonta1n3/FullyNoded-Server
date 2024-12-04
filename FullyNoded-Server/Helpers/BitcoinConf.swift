//
//  BitcoinConf.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

class BitcoinConf {
    
    static func newBitcoinConf() -> String? {
        let d = Defaults.shared
        let prune = d.prune
        let txindex = d.txindex
        let rpcuser = "FullyNoded-Server"
        guard let rpcAuthCreds = RPCAuth().generateCreds(username: rpcuser, password: nil) else { return nil }
        let rpcauth = rpcAuthCreds.rpcAuth
        let data = Data(rpcAuthCreds.rpcPassword.utf8)
        guard let encryptedPass = Crypto.encrypt(data) else { return nil }
        saveCreds(rpcuser: rpcuser, encryptedPass: encryptedPass)
        return """
        \(rpcauth)
        server=1
        prune=\(prune)
        txindex=\(txindex)
        dbcache=\(optimumCache)
        fallbackfee=0.00009
        blocksdir=\(d.blocksDir)
        deprecatedrpc=create_bdb
        """
    }
    
    static func saveCreds(rpcuser: String, encryptedPass: Data) {
        DataManager.retrieve(entityName: .rpcCreds) { existingCreds in
            if let _ = existingCreds {
                DataManager.update(keyToUpdate: "password", newValue: encryptedPass, entity: .rpcCreds) { updated in
                    guard updated else { return }
                    UserDefaults.standard.setValue(rpcuser, forKey: "rpcuser")
                }
            } else {
                DataManager.saveEntity(entityName: .rpcCreds, dict: ["password": encryptedPass]) { saved in
                    guard saved else { return }
                    UserDefaults.standard.setValue(rpcuser, forKey: "rpcuser")
                }
            }
        }
    }
    
    static var optimumCache: Int {
        /// Converts devices ram to gb, divides it by two and converts that to mebibytes. That way we use half the RAM for IBD cache as a reasonable default.
        return Int(((Double(ProcessInfo.processInfo.physicalMemory) / 1073741824.0) / 2.0) * 954.0)
    }
    
    static func getBitcoinConf(completion: @escaping ((conf: [String]?, error: Bool)) -> Void) {
        let path = URL(fileURLWithPath: "\(Defaults.shared.dataDir)/bitcoin.conf")
        guard let bitcoinConf = try? String(contentsOf: path, encoding: .utf8) else {
            completion((nil, false))
            return
        }
        let conf = bitcoinConf.components(separatedBy: "\n")
        completion((conf, false))
    }
    
    class func writeFile(_ path: String, _ fileContents: String) -> Bool {
        let filePath = URL(fileURLWithPath: path)
        guard let file = fileContents.data(using: .utf8) else {
            return false
        }
        return ((try? file.write(to: filePath)) != nil)
    }
    
    class func setBitcoinConf(_ bitcoinConf: String) -> Bool {
        createDirectory(Defaults.shared.dataDir)
        
        return writeFile("\(Defaults.shared.dataDir)/bitcoin.conf", bitcoinConf)
    }
    
    class func createDirectory(_ path: String) {
        let directory = URL(fileURLWithPath: path, isDirectory: true).path
        
        try? FileManager.default.createDirectory(atPath: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [FileAttributeKey.posixPermissions: 0o700])
    }
}
