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
    let headers:Int
    /// Time of the tip block (unix seconds), 0 when unknown.
    let time:Int
    let warnings:String
    var text: String
    
    init(_ dictionary: [String: Any]) {
        network = dictionary["chain"] as? String ?? ""
        blockheight = dictionary["blocks"] as? Int ?? 0
        // NSNumbers: a missing or oddly typed field must not crash the app.
        difficulty = Int((dictionary["difficulty"] as? NSNumber)?.doubleValue ?? 0)
        size_on_disk = (dictionary["size_on_disk"] as? NSNumber)?.intValue ?? 0
        progress = dictionary["progress"] as? String ?? ""
        pruned = dictionary["pruned"] as? Bool ?? false
        verificationprogress = dictionary["verificationprogress"] as? Double ?? 0.0
        pruneheight = dictionary["pruneheight"] as? Int ?? 0
        chain = dictionary["chain"] as? String ?? ""
        blocks = dictionary["blocks"] as? Int ?? 0
        initialblockdownload = dictionary["initialblockdownload"] as? Bool ?? false
        headers = dictionary["headers"] as? Int ?? 0
        time = dictionary["time"] as? Int ?? 0
        // A string before v28, a list of strings since.
        if let list = dictionary["warnings"] as? [String] {
            warnings = list.joined(separator: " ")
        } else {
            warnings = dictionary["warnings"] as? String ?? ""
        }
        text = ""
        for (key, value) in dictionary {
            text += "\(key): \(value)\n"
        }
        
    }
    
    public var description: String {
        return ""
    }
}
