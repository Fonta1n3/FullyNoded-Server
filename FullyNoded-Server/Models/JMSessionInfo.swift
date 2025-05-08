//
//  JMSessionInfo.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 5/7/25.
//


import Foundation

// JSON-RPC error struct
struct JSONRPCError: Codable {
    let code: Int?
    let message: String?
}

// Wrapper for JSON-RPC response
struct JSONRPCResponse<T: Codable>: Codable {
    let result: T?
    let error: JSONRPCError?
    let id: String?
    
    enum CodingKeys: String, CodingKey {
        case result
        case error
        case id
    }
}

// Session information model
struct SessionInfo: Codable {
    let blockHeight: Int?
    let coinjoinInProcess: Bool
    let makerRunning: Bool
    let nickname: String?
    let offerList: String?
    let rescanning: Bool
    let schedule: String?
    let session: Bool
    let walletName: String?
    
    enum CodingKeys: String, CodingKey {
        case blockHeight = "block_height"
        case coinjoinInProcess = "coinjoin_in_process"
        case makerRunning = "maker_running"
        case nickname
        case offerList = "offer_list"
        case rescanning
        case schedule
        case session
        case walletName = "wallet_name"
    }
    
    // Custom decoding to handle 0/1 as Bool
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        blockHeight = try container.decodeIfPresent(Int.self, forKey: .blockHeight)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        offerList = try container.decodeIfPresent(String.self, forKey: .offerList)
        schedule = try container.decodeIfPresent(String.self, forKey: .schedule)
        
        // Handle "None" as nil for walletName
        let walletNameValue = try container.decodeIfPresent(String.self, forKey: .walletName)
        walletName = walletNameValue == "None" ? nil : walletNameValue
        
        // Decode 0/1 as Bool
        let coinjoinValue = try container.decode(Int.self, forKey: .coinjoinInProcess)
        coinjoinInProcess = coinjoinValue != 0
        
        let makerValue = try container.decode(Int.self, forKey: .makerRunning)
        makerRunning = makerValue != 0
        
        let rescanValue = try container.decode(Int.self, forKey: .rescanning)
        rescanning = rescanValue != 0
        
        let sessionValue = try container.decode(Int.self, forKey: .session)
        session = sessionValue != 0
    }
}
