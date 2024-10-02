//
//  TorClient.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/25/24.
//

import Foundation
import Tor

protocol OnionManagerDelegate: AnyObject {
    func torConnProgress(_ progress: Int)
    func torConnFinished()
    func torConnDifficulties()
}

class TorClient: NSObject, URLSessionDelegate {
    
    enum TorState {
        case none
        case started
        case connected
        case stopped
        case refreshing
    }
    
    public var state: TorState = .none
    public var cert:Data?
    
    static let sharedInstance = TorClient()
    private var config: TorConfiguration = TorConfiguration()
    private var thread: TorThread?
    private var controller: TorController?
    private var authDirPath = ""
    var isRefreshing = false
    
    // The tor url session configuration.
    // Start with default config as fallback.
    private lazy var sessionConfiguration: URLSessionConfiguration = .default

    // The tor client url session including the tor configuration.
    lazy var session = URLSession(configuration: sessionConfiguration)
    
    
    // Start the tor client.
    func start(delegate: OnionManagerDelegate?) {
        //session.delegate = self
        weak var weakDelegate = delegate
        state = .started
        
        let proxyPort = 19850
        
        sessionConfiguration.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS,
                                                          kCFStreamPropertySOCKSProxyHost: "localhost",
                                                          kCFStreamPropertySOCKSProxyPort: proxyPort]
        
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
        
        addTorrc()
        
        //add V3 auth keys to ClientOnionAuthDir if any exist
        createTorDirectory()
        //authDirPath = createAuthDirectory()
        
//        clearAuthKeys { [weak self] in
//            guard let self = self else { return }
            
            //self.addAuthKeysToAuthDirectory {
                
                self.thread = nil
                
                self.config.options = [
                    "AutomapHostsOnResolve": "1",
                    "SocksPort": "\(proxyPort)",
                    "AvoidDiskWrites": "1",
                    "LearnCircuitBuildTimeout": "1",
                    "NumEntryGuards": "8",
                    "SafeSocks": "1",
                    "DisableDebuggerAttachment": "1",
                    "SafeLogging": "1",
                    "StrictNodes": "1"
                ]
                
                //self?.config.arguments = ["--defaults-torrc \(NSTemporaryDirectory()).torrc"]
                self.config.cookieAuthentication = true
                self.config.dataDirectory = URL(fileURLWithPath: self.torPath())
                self.config.controlSocket = self.config.dataDirectory?.appendingPathComponent("cp")
                self.thread = TorThread(configuration: self.config)
                
                // Initiate the controller.
                if self.controller == nil {
                    self.controller = TorController(socketURL: self.config.controlSocket!)
                }
                
                // Start a tor thread.
                self.thread?.start()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    // Connect Tor controller.
                    do {
                        if !(self.controller?.isConnected ?? false) {
                            do {
                                try self.controller?.connect()
                            } catch {
                                print("error=\(error)")
                            }
                        }
                        
                        let cookie = try Data(
                            contentsOf: self.config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
                            options: NSData.ReadingOptions(rawValue: 0)
                        )
                        
                        self.controller?.authenticate(with: cookie) { (success, error) in
                            if let error = error {
                                print("error = \(error.localizedDescription)")
                                return
                            }
                            
                            var progressObs: Any? = nil
                            progressObs = self.controller?.addObserver(forStatusEvents: {
                                (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in
                                if arguments != nil {
                                    if arguments!["PROGRESS"] != nil {
                                        let progress = Int(arguments!["PROGRESS"]!)!
                                        print(progress)
                                        weakDelegate?.torConnProgress(progress)
                                        if progress >= 100 {
                                            self.controller?.removeObserver(progressObs)
                                        }
                                        return true
                                    }
                                }
                                return false
                            })
                            
                            var observer: Any? = nil
                            observer = self.controller?.addObserver(forCircuitEstablished: { established in
                                if established {
                                    self.state = .connected
                                    weakDelegate?.torConnFinished()
                                    self.controller?.removeObserver(observer)
                                    
                                } else if self.state == .refreshing {
                                    self.state = .connected
                                    weakDelegate?.torConnFinished()
                                    self.controller?.removeObserver(observer)
                                }
                            })
                        }
                    } catch {
                        weakDelegate?.torConnDifficulties()
                        self.state = .none
                    }
                }
            //}
        //}
    }
    
    
//    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
//        guard let trust = challenge.protectionSpace.serverTrust else {
//            return
//        }
//        
//        let credential = URLCredential(trust: trust)
//        
////        if let certData = self.cert,
////            let remoteCert = SecTrustGetCertificateAtIndex(trust, 0) {
////            let remoteCertData = SecCertificateCopyData(remoteCert) as NSData
////            let certData = Data(base64Encoded: certData)
////
////            if let pinnedCertData = certData,
////                remoteCertData.isEqual(to: pinnedCertData as Data) {
////                print("using cert")
////                completionHandler(.useCredential, credential)
////            } else {
////                completionHandler(.rejectProtectionSpace, nil)
////            }
////        } else {
////            print("using cert")
////            completionHandler(.useCredential, credential)
////        }
//        
//        completionHandler(.useCredential, credential)
//    }
    
    func resign() {
        controller?.disconnect()
        controller = nil
        thread?.cancel()
        thread = nil
        //clearAuthKeys {}
        state = .stopped
    }
    
    private func createTorDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: self.torPath(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Directory previously created.")
        }
    }
    
    private func torPath() -> String {
        return "\(NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "")/tor"
    }
        
    
//    private func createAuthDirectory() -> String {
//        // Create tor v3 auth directory if it does not yet exist
//        let authPath = URL(fileURLWithPath: self.torPath(), isDirectory: true).appendingPathComponent("onion_auth", isDirectory: true).path
//        
//        do {
//            try FileManager.default.createDirectory(atPath: authPath,
//                                                    withIntermediateDirectories: true,
//                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
//        } catch {
//            print("Auth directory previously created.")
//        }
//        
//        return authPath
//    }
    
//    private func addAuthKeysToAuthDirectory(completion: @escaping () -> Void) {
//        
//        CoreDataService.retrieveEntity(entityName: .authKeys) { authKeys in
//            guard let authKeys = authKeys, authKeys.count > 0 else { completion(); return }
//            
//            let authKeysStr = AuthKeysStruct.init(dictionary: authKeys[0])
//            let authorizedKey = decryptedValue(authKeysStr.privateKey)
//            
//            CoreDataService.retrieveEntity(entityName: .newNodes) { [weak self] nodes in
//                guard let self = self, let nodes = nodes, nodes.count > 0 else { completion(); return }
//                
//                for (i, nodeDict) in nodes.enumerated() {
//                    let nodeStruct = NodeStruct(dictionary: nodeDict)
//                    
//                    if nodeStruct.isActive && nodeStruct.onionAddress != nil {
//                        let onionAddress = decryptedValue(nodeStruct.onionAddress!)
//                        let onionAddressArray = onionAddress.components(separatedBy: ".onion:")
//                        // Ensure we are actually V3 before adding auth
//                        guard onionAddressArray[0].count > 55 else { completion(); return }
//                        
//                        let authString = onionAddressArray[0] + ":descriptor:x25519:" + authorizedKey
//                        let suffix = "\(randomString(length: 10)).auth_private"
//                        
//                        let file = URL(fileURLWithPath: self.authDirPath, isDirectory: true).appendingPathComponent(suffix)
//                        
//                        try? authString.write(to: file, atomically: true, encoding: .utf8)
//                        
//                        try? (file as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
//                    }
//                    
//                    if i + 1 == nodes.count {
//                        completion()
//                    }
//                }
//            }
//        }
//    }
    
//    private func clearAuthKeys(completion: @escaping () -> Void) {
//        let fileManager = FileManager.default
//        let authPath = self.authDirPath
//        
//        do {
//            let filePaths = try fileManager.contentsOfDirectory(atPath: authPath)
//            
//            for filePath in filePaths {
//                let url = URL(fileURLWithPath: authPath + "/" + filePath)
//                try fileManager.removeItem(at: url)
//            }
//            
//            completion()
//        } catch {
//            
//            completion()
//        }
//    }
    
    private func addTorrc() {
        createHiddenServiceDirectory()
        let torrcUrl = URL(fileURLWithPath: "/Users/\(NSUserName())/.torrc")
        let torrc = Data(Torrc.torrc.utf8)
        do {
            try torrc.write(to: torrcUrl)
        } catch {
            print("an error happened while creating the file")
        }
    }
    
    private func createHiddenServiceDirectory() {
        let jmHostDir = "\(torPath())/host/joinmarket/"
        let btcMainDir = "\(torPath())/host/bitcoin/rpc/main/"
        let btcTestDir = "\(torPath())/host/bitcoin/rpc/test/"
        let btcRegtestDir = "\(torPath())/host/bitcoin/rpc/regtest/"
        let btcSignetDir = "\(torPath())/host/bitcoin/rpc/signet/"
        
        let hsDirs = [jmHostDir, btcMainDir, btcTestDir, btcRegtestDir, btcSignetDir]
        for hsDir in hsDirs {
            do {
                try FileManager.default.createDirectory(atPath: hsDir,
                                                        withIntermediateDirectories: true,
                                                        attributes: [FileAttributeKey.posixPermissions: 0o700])
            } catch {
                print("Directory previously created.")
            }
        }
    }
    
    func hostnames() -> [String]? {
        let jmHost = "\(torPath())/host/joinmarket/hostname"
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/hostname"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/hostname"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/hostname"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/hostname"
        
        let hosts = [jmHost, btcMain, btcTest, btcSignet, btcRegtest]
        var hostnames: [String] = []
        
        for host in hosts {
            let path = URL(fileURLWithPath: host)
            guard let hs = try? String(contentsOf: path, encoding: .utf8) else { return nil }
            let trimmed = hs.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)

            hostnames.append(trimmed)
        }
        
        return hostnames
    }
    
    func turnedOff() -> Bool {
        return false
    }
}
