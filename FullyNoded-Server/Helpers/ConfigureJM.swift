//
//  ConfigureJM.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/13/25.
//

import Foundation

enum ConfigureJM {
    
    static func configureJm(completion: @escaping ((configured: Bool, error: String?)) -> Void) {
        var chain = UserDefaults.standard.object(forKey: "chain") as? String ?? "main"
        let port = UserDefaults.standard.object(forKey: "port") as? String ?? "8332"
        switch chain {
        case "main": chain = "mainnet"
        case "regtest": chain = "testnet"
        case "test": chain = "testnet"
        default:
            break
        }
        //updateConf(key: "tx_fees", value: "7000")//https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md
        let tempStringPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/.temp"
        let tempDirPath = URL(fileURLWithPath: tempStringPath)
        
        do {
            try FileManager.default.createDirectory(atPath: tempDirPath.path(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion((false, error.localizedDescription))
        }
        
        let cookie = "/Users/\(NSUserName())/.fullynoded/JoinMarket/.temp/.cookie"
        guard let cookieUrl = URL(string: cookie) else {
            completion((false, "Unable to convert cookie string to url."))
            return
        }
        
        guard CreateFNDirConfigureCore.writeFile(cookie, "") else {
            completion((false, "Could not create cookie file."))
            return
        }
        
        guard let creds = RPCAuth().generateCreds(username: "joinmarket", password: nil) else {
            completion((false, "Unable to create rpc creds."))
            return
        }
        
        let cookieContents = "joinmarket:\(creds.rpcPassword)"
        
        do {
            try cookieContents.write(to: cookieUrl, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            completion((false, error.localizedDescription))
        }
        
        updateConf(key: "network", value: chain)
        updateConf(key: "rpc_port", value: port)
        updateConf(key: "rpc_wallet_file", value: "jm_wallet")
        updateConf(key: "tor_control_host", value: "/Users/\(NSUserName())/Library/Caches/tor/cp")
        updateConf(key: "rpc_cookie_file", value: cookie)
        //updateConf(key: "#max_cj_fee_abs", value: "\(Int.random(in: 2200...5000))")
        //updateConf(key: "#max_cj_fee_rel", value: Double.random(in: 0.00199...0.00243).avoidNotation)
        //updateConf(key: "max_cj_fee_abs", value: "\(Int.random(in: 2200...5000))")
        //updateConf(key: "max_cj_fee_rel", value: Double.random(in: 0.00243...0.00421).avoidNotation)
        
        BitcoinConf.getBitcoinConf { (conf, error) in
            guard let existingBitcoinConf = conf else {
                completion((false, "Unable to fetch your bitcoin.conf."))
                return
            }
            
            let cookieAuth = creds.rpcAuth
            let updatedBitcoinConf = existingBitcoinConf.joined(separator: "\n")
            if !updatedBitcoinConf.contains(cookieAuth) {
                let newBitcoinConf = cookieAuth + "\n" + updatedBitcoinConf
                guard BitcoinConf.setBitcoinConf(newBitcoinConf) else {
                    completion((false, "Unable to fetch your bitcoin.conf."))
                    return
                }
            }
            
            BitcoinRPC.shared.command(method: "createwallet", params: ["wallet_name": "jm_wallet", "descriptors": false]) { (result, error) in
                guard error == nil else {
                    if !error!.contains("Database already exists.") {
                        completion((false, error))
                    } else {
                        completion((true, nil))
                    }
                    return
                }
                completion((true, nil))
            }
        }
    }
    
    static func updateConf(key: String, value: String) {
        let jmConfPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"
        guard fileExists(path: jmConfPath) else { return }
        guard let conf = try? Data(contentsOf: URL(fileURLWithPath: jmConfPath)) else {
            return
        }
        guard let string = String(data: conf, encoding: .utf8) else {
            return
        }
        let arr = string.split(separator: "\n")
        for item in arr {
            let uncommentedKey = key.replacingOccurrences(of: "#", with: "")
            if item.hasPrefix("\(key) =") || item.hasPrefix("#\(key) =") {
                let newConf = string.replacingOccurrences(of: item, with: uncommentedKey + " = " + value)
                try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
            } else if item.hasPrefix("rpc_password = ") || item.hasPrefix("rpc_user = ") {
                let newConf = string.replacingOccurrences(of: item, with: "#\(item)")
                try? newConf.write(to: URL(fileURLWithPath: jmConfPath), atomically: false, encoding: .utf8)
            }
        }
    }
    
    static func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
}


