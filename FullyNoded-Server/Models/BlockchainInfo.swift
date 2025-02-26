//
//  BlockchainInfo.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/27/24.
//

import Foundation

public struct BlockchainInfo: CustomStringConvertible {
    let difficulty:Int
    let network:String
    let blockheight:Int
    let size_on_disk:Int
    let progress:String
    let pruned:Bool
    let verificationprogress:Double
    let pruneheight:Int
    let chain:String
    let blocks:Int
    let initialblockdownload:Bool
    var text: String
    
    init(_ dictionary: [String: Any]) {
        network = dictionary["chain"] as? String ?? ""
        blockheight = dictionary["blocks"] as? Int ?? 0
        difficulty = Int(dictionary["difficulty"] as! Double)
        size_on_disk = Int(dictionary["size_on_disk"] as! UInt64)
        progress = dictionary["progress"] as? String ?? ""
        pruned = dictionary["pruned"] as? Bool ?? false
        verificationprogress = dictionary["verificationprogress"] as? Double ?? 0.0
        pruneheight = dictionary["pruneheight"] as? Int ?? 0
        chain = dictionary["chain"] as? String ?? ""
        blocks = dictionary["blocks"] as? Int ?? 0
        initialblockdownload = dictionary["initialblockdownload"] as? Bool ?? false
        text = ""
        for (key, value) in dictionary {
            text += "\(key): \(value)\n"
        }
        
    }
    
    public var description: String {
        return ""
    }
}
