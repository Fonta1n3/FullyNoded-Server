//
//  Scripts.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import Foundation

public enum SCRIPT: String {
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

public enum BTCCONF: String {
    case prune = "prune"
    case txindex = "txindex"
    case mainnet = "mainnet"
    case testnet = "testnet"
    case regtest = "regtest"
    case disablewallet = "disablewallet"
    case datadir = "datadir"
    case blocksdir = "blocksdir"
}