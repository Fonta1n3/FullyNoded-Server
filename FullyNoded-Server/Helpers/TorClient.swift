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
    
    public var showProgress: (((Int)) -> Void)?
    public var torConnected: (((Bool)) -> Void)?
    
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
        weak var weakDelegate = delegate
        state = .started
        
        let proxyPort = 19850
        
        sessionConfiguration.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS,
                                          kCFStreamPropertySOCKSProxyHost: "localhost",
                                          kCFStreamPropertySOCKSProxyPort: proxyPort]
        
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
        
        addTorrc()
        createTorDirectory()
        thread = nil
        
        config.options = [
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
        
        config.cookieAuthentication = true
        config.dataDirectory = URL(fileURLWithPath: torPath())
        config.controlSocket = config.dataDirectory?.appendingPathComponent("cp")
        thread = TorThread(configuration: config)
        
        // Initiate the controller.
        if controller == nil {
            controller = TorController(socketURL: config.controlSocket!)
        }
        
        // Start a tor thread.
        thread?.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            // Connect Tor controller.
            do {
                if !(controller?.isConnected ?? false) {
                    do {
                        try controller?.connect()
                    } catch {
                        print("error=\(error)")
                    }
                }
                
                let cookie = try Data(
                    contentsOf: config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
                    options: NSData.ReadingOptions(rawValue: 0)
                )
                
                controller?.authenticate(with: cookie) { [weak self] (success, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("error = \(error.localizedDescription)")
                        return
                    }
                    
                    var progressObs: Any? = nil
                    progressObs = controller?.addObserver(forStatusEvents: { [weak self]
                        (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in
                        guard let self = self else { return false }
                        if arguments != nil {
                            if arguments!["PROGRESS"] != nil {
                                let progress = Int(arguments!["PROGRESS"]!)!
                                showProgress?((progress))
                                weakDelegate?.torConnProgress(progress)
                                if progress >= 100 {
                                    controller?.removeObserver(progressObs)
                                }
                                return true
                            }
                        }
                        return false
                    })
                    
                    var observer: Any? = nil
                    observer = controller?.addObserver(forCircuitEstablished: { [weak self] established in
                        guard let self = self else { return }
                        if established {
                            state = .connected
                            weakDelegate?.torConnFinished()
                            controller?.removeObserver(observer)
                            
                        } else if state == .refreshing {
                            state = .connected
                            weakDelegate?.torConnFinished()
                            controller?.removeObserver(observer)
                        }
                    })
                }
            } catch {
                weakDelegate?.torConnDifficulties()
                state = .none
            }
        }
    }
    
    func resign() {
        controller?.disconnect()
        controller = nil
        thread?.cancel()
        thread = nil
        state = .stopped
    }
    
    private func createTorDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: torPath(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Directory previously created.")
        }
    }
    
    private func torPath() -> String {
        return "\(NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "")/tor"
    }
    
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
        let clnDir = "\(torPath())/host/cln/rpc/"
        
        let hsDirs = [jmHostDir, btcMainDir, btcTestDir, btcRegtestDir, btcSignetDir, clnDir]
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
        let clnDir = "\(torPath())/host/cln/rpc/hostname"
        
        let hosts = [jmHost, btcMain, btcTest, btcSignet, btcRegtest, clnDir]
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
