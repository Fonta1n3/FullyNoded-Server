//
//  Crypto.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/11/24.
//

import Foundation
import CryptoKit

class Crypto {
    static let encKeyUnify = UserDefaults.standard.value(forKey: "encKeyFullyNodedServer") as! String
    
    static func encrypt(_ data: Data) -> Data? {
        guard let key = KeyChain.getData(encKeyUnify) else {
            if KeyChain.set(Crypto.privKeyData(), forKey: encKeyUnify) {
                return encrypt(data)
            } else {
                return nil
            }
        }
        
        return try? ChaChaPoly.seal(data, using: SymmetricKey(data: key)).combined
    }
    
    
    static func decrypt(_ data: Data) -> Data? {
        guard let key = KeyChain.getData(encKeyUnify),
            let box = try? ChaChaPoly.SealedBox.init(combined: data) else {
                return nil
        }
        
        return try? ChaChaPoly.open(box, using: SymmetricKey(data: key))
    }
    
    static func privKeyData() -> Data {
        return Curve25519.KeyAgreement.PrivateKey.init().rawRepresentation
    }
}
