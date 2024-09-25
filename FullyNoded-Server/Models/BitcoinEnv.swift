//
//  BitcoinEnv.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/11/24.
//

import Foundation

public struct BitcoinEnvValues: CustomStringConvertible {
    let binaryName: String
    let version: String
    let prefix: String
    let dataDir: String
    let chain: String
    
    init(dictionary: [String: Any]) {
        binaryName = dictionary["binaryName"] as! String
        version = dictionary["version"] as! String
        prefix = dictionary["prefix"] as! String
        dataDir = dictionary["dataDir"] as! String
        chain = dictionary["chain"] as! String
    }
    
    public var description: String {
        return ""
    }
}
