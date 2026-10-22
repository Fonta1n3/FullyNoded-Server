//
//  ConfigureJM.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/13/25.
//

import Foundation

enum ConfigureJM {
    
    static let confPath = "/Users/\(NSUserName())/Library/Application Support/joinmarket/joinmarket.cfg"

    /// joinmarket.cfg's `network` for a bitcoind chain (JoinMarket runs regtest as "testnet").
    static func jmNetwork(chain: String) -> String {
        switch chain {
        case "main": return "mainnet"
        case "regtest", "test", "testnet4": return "testnet"
        default: return chain
        }
    }

    /// Points JoinMarket at the node's current network and RPC port.
    static func configureNetwork() {
        let chain = UserDefaults.standard.object(forKey: "chain") as? String ?? "main"
        let port = UserDefaults.standard.object(forKey: "port") as? String ?? "8332"
        updateConf(key: "network", value: jmNetwork(chain: chain))
        updateConf(key: "rpc_port", value: port)
    }

    /// The (uncommented) value of `key` in joinmarket.cfg.
    static func confValue(_ key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: confPath),
              let conf = String(data: data, encoding: .utf8) else { return nil }
        for line in conf.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) =") || trimmed.hasPrefix("\(key)=") else { continue }
            return trimmed.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
    
    static func configureJm(completion: @escaping ((configured: Bool, error: String?)) -> Void) {
        ConfigureJM.configureNetwork()
        //updateConf(key: "tx_fees", value: "7000")//https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md
        let tempStringPath = "/Users/\(NSUserName())/.fullynoded/JoinMarket/.temp"
        let tempDirPath = URL(fileURLWithPath: tempStringPath)
        
        do {
            try FileManager.default.createDirectory(atPath: tempDirPath.path(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion((false, error.localizedDescription))
            return
        }
        
        let cookie = "/Users/\(NSUserName())/.fullynoded/JoinMarket/.temp/.cookie"
        guard let cookieUrl = URL(string: cookie) else {
            completion((false, "Unable to convert cookie string to url."))
            return
        }
        
        guard ConfigureCore.writeFile(cookie, "") else {
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
            return
        }
        
        
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
    
    /// Sets `key = value` in joinmarket.cfg (uncommenting it if needed) and comments out
    /// rpc_user / rpc_password: JoinMarket uses the cookie file. The file is rewritten once, line by
    /// line, so one change can't undo another (as writing per matching line did before).
    static func updateConf(key: String, value: String) {
        guard let data = FileManager.default.contents(atPath: confPath),
              let conf = String(data: data, encoding: .utf8) else { return }
        let uncommentedKey = key.replacingOccurrences(of: "#", with: "")
        var updated = false
        let lines = conf.components(separatedBy: "\n").map { line -> String in
            if !updated && (line.hasPrefix("\(uncommentedKey) =") || line.hasPrefix("#\(uncommentedKey) =")) {
                updated = true
                return uncommentedKey + " = " + value
            }
            if line.hasPrefix("rpc_password = ") || line.hasPrefix("rpc_user = ") {
                return "#" + line
            }
            return line
        }
        let newConf = lines.joined(separator: "\n")
        if newConf != conf {
            try? newConf.write(toFile: confPath, atomically: true, encoding: .utf8)
        }
    }
    
    static func fileExists(path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
}


