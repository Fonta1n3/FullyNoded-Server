//
//  BitcoinConf.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

class BitcoinConf {
    
    static func bitcoinConf() -> String? {
        let d = Defaults.shared
        let prune = d.prune
        let txindex = d.txindex
        let walletDisabled = d.walletdisabled
        var rpcauth = "#rpcauth="
        let rpcuser = "FullyNoded-Server"
        if let rpcAuthCreds = RPCAuth().generateCreds(username: rpcuser, password: nil) {
            rpcauth = rpcAuthCreds.rpcAuth
            UserDefaults.standard.setValue(rpcAuthCreds.rpcPassword, forKey: "rpcpassword")
            UserDefaults.standard.setValue(rpcuser, forKey: "rpcuser")
        }
        //externalip=\(TorClient.sharedInstance.p2pHostname(chain: "main") ?? "")
        //externalip=\(TorClient.sharedInstance.p2pHostname(chain: "test") ?? "")
        //externalip=\(TorClient.sharedInstance.p2pHostname(chain: "signet") ?? "")
        
        return """
        disablewallet=\(walletDisabled)
        server=1
        prune=\(prune)
        txindex=\(txindex)
        dbcache=\(optimumCache)
        maxconnections=20
        maxuploadtarget=500
        fallbackfee=0.00009
        blocksdir=\(d.blocksDir)
        proxy=127.0.0.1:19150
        listen=1
        discover=1
        \(rpcauth)
        rpcwhitelist=\(rpcuser):\(rpcWhiteList)
        [main]
        rpcport=8332
        rpcallowip=127.0.0.1
        rpcbind=127.0.0.1
        [test]
        rpcport=18332
        rpcallowip=127.0.0.1
        rpcbind=127.0.0.1
        [regtest]
        rpcport=18443
        rpcallowip=127.0.0.1
        rpcbind=127.0.0.1
        [signet]
        rpcport=38332
        rpcallowip=127.0.0.1
        rpcbind=127.0.0.1
        """
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
    
    class func setBitcoinConf(_ bitcoinConf: String) -> Bool {
        createDirectory(Defaults.shared.dataDir)
        
        return writeFile("\(Defaults.shared.dataDir)/bitcoin.conf", bitcoinConf)
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
}
