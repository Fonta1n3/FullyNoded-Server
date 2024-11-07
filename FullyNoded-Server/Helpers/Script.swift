//
//  Scripts.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import Foundation

public enum SCRIPT: String {
    case reindex
    case stopJm
    case launchJmStarter
    case startJm
    case launchJMInstaller
    case installJoinMarket
    case getRune
    case lightningNodeId
    case killBitcoind
    case stopLightning
    case startLightning
    case lightingRunning
    case lightningInstalled
    case launchLightningInstall
    case installLightning
    case checkForBrew
    case launchVerifier
    case launchInstaller
    case hasBitcoinShutdownCompleted
    case isBitcoindRunning
    case didBitcoindStart
    case installHomebrew
    case installXcode
    case openFile
    case verifyBitcoin
    case checkForBitcoin
    case installBitcoin
    case checkXcodeSelect
    case getStrapped
    case launchStrap
    case isBitcoinOn
    case deleteWallet
    case startBitcoin
    
    var stringValue:String {
        switch self {
        case .reindex:
            return "Reindex"
        case .stopJm:
            return "StopJm"
        case .launchJmStarter:
            return "LaunchJMStarter"
        case .startJm:
            return "StartJm"
        case .launchJMInstaller:
            return "LaunchJMInstaller"
        case .installJoinMarket:
            return "InstallJoinMarket"
        case .getRune:
            return "GetRune"
        case .lightningNodeId:
            return "LightningNodeId"
        case .killBitcoind:
            return "KillBitcoind"
        case .stopLightning:
            return "StopLightning"
        case.startLightning:
            return "StartLightning"
        case .lightingRunning:
            return "IsLightningOn"
        case .lightningInstalled:
            return "CheckForLightning"
        case .launchLightningInstall:
            return "LaunchLightningInstall"
        case .installLightning:
            return "InstallLightning"
        case .checkForBrew:
            return "BrewInstalled"
        case .launchVerifier:
            return "LaunchVerifier"
        case .launchInstaller:
            return "LaunchInstaller"
        case .hasBitcoinShutdownCompleted, .isBitcoindRunning, .didBitcoindStart:
            return "IsProcessRunning"
        case .installHomebrew:
            return "LaunchBrewInstall"
        case .installXcode:
            return "LaunchXcodeInstall"
        case .openFile:
            return "OpenFile"
        case .verifyBitcoin:
            return "Verify"
        case .checkForBitcoin:
            return "CheckForBitcoinCore"
        case .installBitcoin:
            return "InstallBitcoin"
        case .checkXcodeSelect:
            return "CheckXCodeSelect"
        case .getStrapped:
            return "Strap"
        case .launchStrap:
            return "LaunchStrap"
        case .isBitcoinOn:
            return "IsBitcoinOn"
        case .deleteWallet:
            return "DeleteWallet"
        case .startBitcoin:
            return "StartBitcoin"
        }
    }
}

//public enum BTCCONF: String {
//    case prune = "prune"
//    case txindex = "txindex"
//    case mainnet = "mainnet"
//    case testnet = "testnet"
//    case regtest = "regtest"
//    case disablewallet = "disablewallet"
//    case datadir = "datadir"
//    case blocksdir = "blocksdir"
//}

public enum ScriptUtil {
    static func runScript(script: SCRIPT, env: [String: String]?, args: [String]?, completion: @escaping ((output: String?, rawData: Data?, errorMessage: String?)) -> (Void)) {
        #if DEBUG
        print("run script: \(script.stringValue)")
        #endif
        
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            let resource = script.stringValue
            guard let path = Bundle.main.path(forResource: resource, ofType: "command") else { return }
            let stdOut = Pipe()
            let stdErr = Pipe()
            let task = Process()
            task.launchPath = path
            if let args = args {
                task.arguments = args
            }
            if let env = env {
                task.environment = env
            }
            
            task.standardOutput = stdOut
            task.standardError = stdErr
            task.launch()
            task.waitUntilExit()
            let data = stdOut.fileHandleForReading.readDataToEndOfFile()
            let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            let errorOutput = String(data: errData, encoding: .utf8)
            completion((output, data, errorOutput))
        }
    }
}


