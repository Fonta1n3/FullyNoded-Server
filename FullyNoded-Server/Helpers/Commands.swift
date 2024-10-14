//
//  Commands.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import Foundation

let rootUrl = "api/v1"

public enum JM_REST {
//    case recover
//    case walletall
//    case walletcreate
    case session
//    case lockwallet(jmWallet: JMWallet)
//    case unlockwallet(jmWallet: JMWallet, password: String)
//    case walletdisplay(jmWallet: JMWallet)
//    case getaddress(jmWallet: JMWallet, mixdepth: Int)
//    case coinjoin(jmWallet: JMWallet)
//    case makerStart(jmWallet: JMWallet)
//    case makerStop(jmWallet: JMWallet)
//    case takerStop(jmWallet: JMWallet)
//    case configGet(jmWallet: JMWallet)
//    case configSet(jmWallet: JMWallet)
//    case gettimelockaddress(jmWallet: JMWallet, date: String)
//    case getSeed(jmWallet: JMWallet)
//    case unfreeze(jmWallet: JMWallet)
//    case listutxos(jmWallet: JMWallet)
//    case directSend(jmWallet: JMWallet)
//    case token(jmWallet: JMWallet)
//    case getinfo
    
    var stringValue:String {
        switch self {
//        case .recover:
//            return "\(rootUrl)/wallet/recover"
//        case .getinfo:
//            return "\(rootUrl)/getinfo"
//        case .token(let wallet):
//            return "\(rootUrl)/token"
//        case .walletall:
//            return "\(rootUrl)/wallet/all"
        case .session:
            return "\(rootUrl)/session"
//        case .walletcreate:
//            return "\(rootUrl)/wallet/create"
//        case .lockwallet(let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/lock"
//        case .unlockwallet(jmWallet: let wallet, _):
//            return "\(rootUrl)/wallet/\(wallet.name)/unlock"
//        case .walletdisplay(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/display"
//        case .getaddress(jmWallet: let wallet, mixdepth: let mixdepth):
//            return "\(rootUrl)/wallet/\(wallet.name)/address/new/\(mixdepth)"
//        case .coinjoin(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/taker/coinjoin"
//        case .makerStart(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/maker/start"
//        case .makerStop(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/maker/stop"
//        case .takerStop(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/taker/stop"
//        case .configGet(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/configget"
//        case .configSet(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/configset"
//        case .gettimelockaddress(jmWallet: let wallet, date: let date):
//            return "\(rootUrl)/wallet/\(wallet.name)/address/timelock/new/\(date)"
//        case .getSeed(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/getseed"
//        case .unfreeze(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/freeze"
//        case .listutxos(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/utxos"
//        case .directSend(jmWallet: let wallet):
//            return "\(rootUrl)/wallet/\(wallet.name)/taker/direct-send"
        }
    }
}
