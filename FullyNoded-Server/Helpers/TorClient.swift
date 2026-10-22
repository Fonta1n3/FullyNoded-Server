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
    /// Called on the main queue with the running tor's version (e.g. "0.4.9.3"), read from
    /// the control port, so it always matches the bundled tor.
    public var showVersion: ((String) -> Void)?
    /// The running tor's version, once known.
    public private(set) var version: String?
    /// Bootstrap progress, 0–100 (main queue).
    public private(set) var progress = 0
    /// Why tor couldn't be started or controlled, if it couldn't.
    public private(set) var lastError: String?
    /// Turned off with Stop: tor keeps running in this process with its network disabled.
    /// (An in-process tor can't be shut down and started again, so Stop/Start toggle
    /// `DisableNetwork` instead.)
    public private(set) var isPaused = false
    
    static let sharedInstance = TorClient()
    static let socksPort = 19850
    /// The control connection is up, so tor can be stopped and started.
    var canPause: Bool { controller?.isConnected ?? false }
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
    /// Starts tor once per launch; later calls only turn its network back on if it was stopped.
    func start(delegate: OnionManagerDelegate?) {
        if thread != nil {
            if isPaused { resume() }
            return
        }
        weak var weakDelegate = delegate
        state = .started
        progress = 0
        lastError = nil
        
        let proxyPort = Self.socksPort
        
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
                    try controller?.connect()
                }
                
                let cookie = try Data(
                    contentsOf: config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
                    options: NSData.ReadingOptions(rawValue: 0)
                )
                
                controller?.authenticate(with: cookie) { [weak self] (success, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        DispatchQueue.main.async {
                            self.lastError = "Couldn't authenticate to tor's control port: \(error.localizedDescription)"
                            self.state = .none
                        }
                        return
                    }

                    // "GETINFO version" → e.g. "0.4.9.3 (git-…)": keep the version number.
                    controller?.getInfoForKeys(["version"]) { [weak self] values in
                        guard let self = self,
                              let version = values.first?.split(separator: " ").first.map(String.init),
                              !version.isEmpty else { return }
                        DispatchQueue.main.async {
                            self.version = version
                            self.showVersion?(version)
                        }
                    }

                    var progressObs: Any? = nil
                    progressObs = controller?.addObserver(forStatusEvents: { [weak self]
                        (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in
                        guard let self = self else { return false }
                        if arguments != nil {
                            if let progress = arguments?["PROGRESS"].flatMap({ Int($0) }) {
                                DispatchQueue.main.async {
                                    self.progress = progress
                                    self.showProgress?((progress))
                                }
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
                        if established || state == .refreshing {
                            DispatchQueue.main.async {
                                self.state = .connected
                                self.progress = 100
                            }
                            weakDelegate?.torConnFinished()
                            controller?.removeObserver(observer)
                        }
                    })

                    // The observers only see events from now on, but with a cached consensus tor
                    // can finish bootstrapping in the second before the controller connects. Ask
                    // where it is, so the UI doesn't sit at 0% waiting for an event already sent.
                    controller?.getInfoForKeys(["status/bootstrap-phase", "status/circuit-established"]) { [weak self] values in
                        guard let self = self, values.count == 2 else { return }
                        // e.g. "NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY=\"Done\"".
                        let progress = values[0].split(separator: " ")
                            .first { $0.hasPrefix("PROGRESS=") }
                            .flatMap { Int($0.dropFirst("PROGRESS=".count)) }
                        let established = values[1].trimmingCharacters(in: .whitespaces) == "1"
                        DispatchQueue.main.async {
                            if let progress = progress {
                                self.progress = progress
                                self.showProgress?(progress)
                                weakDelegate?.torConnProgress(progress)
                                if progress >= 100 { self.controller?.removeObserver(progressObs) }
                            }
                            if established, self.state != .connected {
                                self.state = .connected
                                weakDelegate?.torConnFinished()
                                self.controller?.removeObserver(observer)
                            }
                        }
                    }
                }
            } catch {
                weakDelegate?.torConnDifficulties()
                self.state = .none
                self.lastError = "Couldn't connect to tor's control port: \(error.localizedDescription)"
            }
        }
    }

    /// Takes tor offline (no circuits, onion services unreachable) without ending it.
    func pause(completion: ((Bool) -> Void)? = nil) {
        guard let controller = controller, controller.isConnected else {
            completion?(false)
            return
        }
        controller.setConfForKey("DisableNetwork", withValue: "1") { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.isPaused = true
                    self.state = .stopped
                    self.progress = 0
                } else {
                    self.lastError = "Couldn't stop tor: \(error?.localizedDescription ?? "unknown error")"
                }
                completion?(success)
            }
        }
    }

    /// Brings tor back online after `pause()`, and follows its bootstrap again.
    func resume(completion: ((Bool) -> Void)? = nil) {
        guard let controller = controller, controller.isConnected else {
            completion?(false)
            return
        }
        state = .started
        progress = 0
        controller.setConfForKey("DisableNetwork", withValue: "0") { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.isPaused = false
                    self.followBootstrap()
                } else {
                    self.state = .stopped
                    self.lastError = "Couldn't start tor: \(error?.localizedDescription ?? "unknown error")"
                }
                completion?(success)
            }
        }
    }

    /// New circuits for new connections, and reloads the torrc (SIGNAL RELOAD + NEWNYM).
    func newCircuits(completion: ((Bool) -> Void)? = nil) {
        guard let controller = controller, controller.isConnected else {
            completion?(false)
            return
        }
        controller.resetConnection { success in
            DispatchQueue.main.async { completion?(success) }
        }
    }

    /// Polls the bootstrap phase until tor is connected again (events may already have passed).
    private func followBootstrap(attempt: Int = 0) {
        guard !isPaused, attempt < 120 else { return }
        controller?.getInfoForKeys(["status/bootstrap-phase", "status/circuit-established"]) { [weak self] values in
            DispatchQueue.main.async {
                guard let self = self, values.count == 2 else { return }
                let progress = values[0].split(separator: " ")
                    .first { $0.hasPrefix("PROGRESS=") }
                    .flatMap { Int($0.dropFirst("PROGRESS=".count)) }
                if let progress = progress {
                    self.progress = progress
                    self.showProgress?(progress)
                }
                if values[1].trimmingCharacters(in: .whitespaces) == "1" && (progress ?? 100) >= 100 {
                    self.state = .connected
                    self.progress = 100
                    self.showProgress?(100)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.followBootstrap(attempt: attempt + 1) }
                }
            }
        }
    }

    /// The onion services in the torrc.
    enum OnionService: CaseIterable {
        case joinMarket, bitcoinMain, bitcoinTest, bitcoinSignet, bitcoinRegtest, bitcoinTestnet4

        var directory: String {
            switch self {
            case .joinMarket: return "host/joinmarket"
            case .bitcoinMain: return "host/bitcoin/rpc/main"
            case .bitcoinTest: return "host/bitcoin/rpc/test"
            case .bitcoinSignet: return "host/bitcoin/rpc/signet"
            case .bitcoinRegtest: return "host/bitcoin/rpc/regtest"
            case .bitcoinTestnet4: return "host/bitcoin/rpc/testnet4"
            }
        }

        var port: Int {
            switch self {
            case .joinMarket: return 28183
            case .bitcoinMain: return 8332
            case .bitcoinTest: return 18332
            case .bitcoinSignet: return 38332
            case .bitcoinRegtest: return 18443
            case .bitcoinTestnet4: return 48332
            }
        }

        var title: String {
            switch self {
            case .joinMarket: return "JoinMarket"
            case .bitcoinMain: return "Bitcoin RPC · Mainnet"
            case .bitcoinTest: return "Bitcoin RPC · Testnet3"
            case .bitcoinSignet: return "Bitcoin RPC · Signet"
            case .bitcoinRegtest: return "Bitcoin RPC · Regtest"
            case .bitcoinTestnet4: return "Bitcoin RPC · Testnet4"
            }
        }

        static func bitcoin(chain: String) -> OnionService? {
            switch chain {
            case "main": return .bitcoinMain
            case "test": return .bitcoinTest
            case "signet": return .bitcoinSignet
            case "regtest": return .bitcoinRegtest
            case "testnet4": return .bitcoinTestnet4
            default: return nil
            }
        }
    }

    /// The service's onion address, once tor has created it.
    func hostname(for service: OnionService) -> String? {
        let path = "\(torPath())/\(service.directory)/hostname"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let host = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
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
        let btcTestnet4 = "\(torPath())/host/bitcoin/rpc/testnet4/"
        let clnDir = "\(torPath())/host/cln/rpc/"
        
        let hsDirs = [jmHostDir, btcMainDir, btcTestDir, btcRegtestDir, btcSignetDir, btcTestnet4, clnDir]
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
        let btcTestnet4 = "\(torPath())/host/bitcoin/rpc/testnet4/hostname"
        let clnDir = "\(torPath())/host/cln/rpc/hostname"
        
        let hosts = [jmHost, btcMain, btcTest, btcSignet, btcRegtest, btcTestnet4, clnDir]
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
