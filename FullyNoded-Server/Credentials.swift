//
//  Credentials.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

public struct Credentials: CustomStringConvertible {
    let rpcAuth:String
    let rpcPassword:String
    
    init(_ dict: [String:String]) {
        rpcAuth = dict["rpcAuth"]!
        rpcPassword = dict["rpcPassword"]!
    }
    
    public var description: String {
        return ""
    }
}
