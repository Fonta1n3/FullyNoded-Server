//
//  ExplorerRPC.swift
//  FullyNoded-Server
//
//  The explorer's one way to the node: the local bitcoind of the network selected in FN-Server.
//  It only reads, apart from a UTXO scan's start and abort.
//

import Foundation

struct ExplorerError: Error {
    let message: String
    /// Bitcoin Core's error code, if it was one.
    var code: Int? = nil
    init(_ message: String, code: Int? = nil) {
        self.message = message
        self.code = code
    }
}

enum ExplorerRPC {
    static func call(_ method: String, _ params: [String: Any] = [:], wallet: String? = nil, timeout: TimeInterval = 120) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            BitcoinRPC.shared.spCommand(method: method, params: params, wallet: wallet, timeout: timeout) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(.rpc(let code, let message)):
                    continuation.resume(throwing: ExplorerError(message, code: code))
                case .failure(let error):
                    continuation.resume(throwing: ExplorerError(error.description))
                }
            }
        }
    }
}
