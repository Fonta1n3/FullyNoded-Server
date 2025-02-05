//
//  BitcoinKnots.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/24/25.
//

//import SwiftUI
//
//struct BitcoinKnots: View {
//    
//    @Environment(\.openWindow) var openWindow
//    @Environment(\.scenePhase) var scenePhase
//    @State private var syncedAmount = 0.0
//    @State private var statusText = ""
//    @State private var showError = false
//    @State private var message = ""
//    @State private var isRunning = false
//    @State private var isAnimating = false
//    @State private var logOutput = ""
//    @State private var selectedChain = UserDefaults.standard.string(forKey: "knotsChain") ?? "main"
//    @State private var env: [String: String] = [:]
//    @State private var blockchainInfo: BlockchainInfo? = nil
//    @State private var timerForBitcoinStatus = Timer.publish(every: 15.0, on: .main, in: .common).autoconnect()
//    private var chains = ["main", "test", "signet", "regtest"]
//    
//    
//    var body: some View {
//        FNIcon()
//        VStack() {
//            HStack() {
//                Image(systemName: "server.rack")
//                    .padding(.leading)
//                if let version = env["VERSION"] {
//                    Text("Bitcoin Core Server v\(version)")
//                } else {
//                    Text("Bitcoin Core Server")
//                }
//                Spacer()
//                Button {
//                    openWindow(id: "QuickConnect")
//                } label: {
//                    Image(systemName: "qrcode")
//                }
//                .padding([.trailing])
//                Button {
//                    openWindow(id: "Utilities")
//                } label: {
//                    Image(systemName: "wrench.and.screwdriver")
//                }
//                .padding([.trailing])
//                Button {
//                    isBitcoinCoreRunning()
//                } label: {
//                    Image(systemName: "arrow.clockwise")
//                }
//                .padding([.trailing])
//            }
//            .padding([.leading, .trailing])
//            .frame(maxWidth: .infinity, alignment: .leading)
//            
//            HStack() {
//                Picker("Blockchain", selection: $selectedChain) {
//                    ForEach(chains, id: \.self) {
//                        Text($0)
//                    }
//                }
//                .padding([.leading])
//                .onChange(of: selectedChain) {
//                    updateChain(chain: selectedChain)
//                    isBitcoinCoreRunning()
//                }
//                .frame(width: 180)
//                
//                if let blockchainInfo = blockchainInfo, blockchainInfo.initialblockdownload, isRunning {
//                    Label {
//                        Text("Downloading the blockchain...")
//                            .foregroundStyle(.secondary)
//                    } icon: {
//                        ProgressView()
//                            .scaleEffect(0.5)
//                    }
//                }
//                if isAnimating {
//                    ProgressView()
//                        .scaleEffect(0.5)
//                }
//                if isRunning {
//                    if isAnimating {
//                        Image(systemName: "circle.fill")
//                            .foregroundStyle(.orange)
//                        Text(statusText)
//                    } else {
//                        Image(systemName: "circle.fill")
//                            .foregroundStyle(.green)
//                        Text("Running")
//                    }
//                    
//                } else {
//                    if isAnimating {
//                        Image(systemName: "circle.fill")
//                            .foregroundStyle(.orange)
//                        Text(statusText)
//                    } else {
//                        Image(systemName: "circle.fill")
//                            .foregroundStyle(.red)
//                        Text("Stopped")
//                    }
//                }
//                if !isRunning, !isAnimating {
//                    Button {
//                        startBitcoinCore()
//                    } label: {
//                        Text("Start")
//                    }
//                } else if !isAnimating {
//                    Button {
//                        stopBitcoinCore()
//                    } label: {
//                        Text("Stop")
//                    }
//                }
//            }
//            .padding([.leading])
//            .frame(maxWidth: .infinity, alignment: .leading)
//            
//            VStack() {
//                if let blockchainInfo = blockchainInfo {
//                    if blockchainInfo.progressString == "Fully verified" {
//                        Label {
//                            Text(blockchainInfo.progressString)
//                        } icon: {
//                            Image(systemName: "checkmark.seal.fill")
//                                .foregroundStyle(.green)
//                        }
//                        .padding([.leading])
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    } else if isRunning {
//                        HStack() {
//                            ProgressView("Verification progress \(Int(syncedAmount * 100))% complete", value: syncedAmount, total: 1)
//                                .padding([.leading, .trailing])
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                            Spacer()
//                        }
//                    }
//                }
//                if logOutput != "" {
//                    Label {
//                        Text(logOutput)
//                    } icon: {
//                        Image(systemName: "info.circle")
//                    }
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .padding([.leading, .trailing, .bottom, .top])
//                    .foregroundStyle(.secondary)
//                } else {
//                    Text("")
//                }
//                
//                EmptyView()
//                    .onReceive(timerForBitcoinStatus) { _ in
//                        isBitcoinCoreRunning()
//                    }
//            }
//            .padding([.leading, .bottom])
//        }
//        .onChange(of: scenePhase) { oldPhase, newPhase in
//            if newPhase == .active {
//                updateTimer(interval: 15.0)
//            } else if newPhase == .inactive {
//                timerForBitcoinStatus.upstream.connect().cancel()
//            } else if newPhase == .background {
//                timerForBitcoinStatus.upstream.connect().cancel()
//            }
//        }
//        .padding([.top])
//        .cornerRadius(8)
//        .overlay(
//            RoundedRectangle(cornerRadius: 8)
//                .stroke(.secondary, lineWidth: 1)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .padding([.leading, .trailing, .bottom])
//        )
//        .onAppear(perform: {
//            initialLoad()
//        })
//        .alert(message, isPresented: $showError) {
//            Button("OK", role: .cancel) {}
//        }
//        Spacer()
//    }
//    
//    private func fileExists(path: String) -> Bool {
//        return FileManager.default.fileExists(atPath: path)
//    }
//    
//    private func conf(stringPath: String) -> String? {
//        guard fileExists(path: stringPath) else {
//            #if DEBUG
//            print("file does not exists at: \(stringPath)")
//            #endif
//            return nil
//        }
//        
//        let url = URL(fileURLWithPath: stringPath)
//        if let conf = try? Data(contentsOf: url) {
//            guard let string = String(data: conf, encoding: .utf8) else {
//                showMessage(message: "Can not encode data as utf8 string.")
//                return nil
//            }
//            return string
//        } else if let conf = try? String(contentsOf: url) {
//            return conf
//        } else {
//            showMessage(message: "No contents found.")
//            return nil
//        }
//    }
//    
//    
//    
//    private func initialLoad() {
//        selectedChain = UserDefaults.standard.string(forKey: "knotsChain") ?? "main"
//        DataManager.retrieve(entityName: .bitcoinEnv) { env in
//            guard let env = env else { return }
//            let envValues = BitcoinEnvValues(dictionary: env)
//            self.env = [
//                "BINARY_NAME": envValues.binaryName,
//                "VERSION": envValues.version,
//                "PREFIX": envValues.prefix,
//                "DATADIR": Defaults.shared.bitcoinKnotsDataDir,
//                "knotsChain": envValues.chain
//            ]
//            isBitcoinCoreRunning()
//        }
//    }
//    
//    private func updateChain(chain: String) {
//        var port = "8332"
//        switch chain {
//        case "signet": port = "38332"
//        case "regtest": port = "18443"
//        case "test": port = "18332"
//        default: port = "8332"
//        }
//        UserDefaults.standard.setValue(port, forKey: "knotsPort")
//        UserDefaults.standard.setValue(chain.lowercased(), forKey: "knotsChain")
//        self.env["knotsChain"] = chain
//        self.blockchainInfo = nil
//        self.logOutput = ""
//        DataManager.update(keyToUpdate: "knotsChain", newValue: chain, entity: .bitcoinEnv) { updated in
//            guard updated else {
//                showMessage(message: "There was an issue updating your network...")
//                return
//            }
//            isBitcoinCoreRunning()
//            showBitcoinLog()
//        }
//    }
//    
//    
//    
//    private func updateTimer(interval: Double) {
//        timerForBitcoinStatus.upstream.connect().cancel()
//        timerForBitcoinStatus = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
//    }
//    
//    private func startBitcoinCore() {
//        isAnimating = true
//        statusText = "Starting.."
//        ScriptUtil.runScript(script: .startBitcoin, env: env, args: nil) { (output, rawData, errorMessage) in
//           updateTimer(interval: 3.0)
//        }
//    }
//    
//    private func parseDidBitcoinStart(result: String) {
//        if !result.contains("Stopped") {
//            isBitcoinCoreRunning()
//        }
//    }
//    
//    private func stopBitcoinCore() {
//        isAnimating = true
//        statusText = "Stopping..."
//        BitcoinRPC.shared.command(method: "stop", params: [:]) { (result, error) in
//            updateTimer(interval: 3.0)
//            
//            guard let result = result as? String else {
//                isAnimating = false
//                showMessage(message: error ?? "Unknown issue turning off Bitcoin Core.")
//                return
//            }
//            
//            self.showBitcoinLog()
//            self.stopBitcoinParse(result: result)
//        }
//    }
//    
//    private func stopBitcoinParse(result: String) {
//        if result.contains("Shutdown: done") {
//            isRunning = false
//            isAnimating = false
//            blockchainInfo = nil
//            timerForBitcoinStatus.upstream.connect().cancel()
//        } else {
//            isRunning = true
//        }
//    }
//    
//    private func showBitcoinLog() {
//        guard let debugPath = debugLogPath() else { return }
//        
//        let path = URL(fileURLWithPath: debugPath)
//        
//        guard let log = try? String(contentsOf: path, encoding: .utf8) else {
//            return
//        }
//        
//        let logItems = log.components(separatedBy: "\n")
//        
//        DispatchQueue.main.async {
//            if logItems.count > 2 {
//                let lastLogItem = "\(logItems[logItems.count - 2])"
//                logOutput = lastLogItem
//                if lastLogItem.contains("Shutdown: done") {
//                    isRunning = false
//                }
//            }
//        }
//    }
//    
//    private func debugLogPath() -> String? {
//        let chain = Defaults.shared.chain
//        var debugLogPath: String?
//        switch chain {
//        case "main":
//            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/debug.log"
//        case "test":
//            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/testnet3/debug.log"
//        case "regtest":
//            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/regtest/debug.log"
//        case "signet":
//            debugLogPath = "\(Defaults.shared.bitcoinCoreDataDir)/signet/debug.log"
//        default:
//            break
//        }
//        return debugLogPath
//    }
//    
//    private func isBitcoinCoreRunning() {
//        isAnimating = true
//        statusText = "Refreshing..."
//        BitcoinRPC.shared.command(method: "getblockchaininfo", params: [:]) { (result, error) in
//            showBitcoinLog()
//            guard error == nil, let result = result as? [String: Any] else {
//                if let error = error {
//                    handleRPCError(error: error)
//                }
//                return
//            }
//            isAnimating = false
//            updateTimer(interval: 15.0)
//            let blockchainInfo = BlockchainInfo(result)
//            self.blockchainInfo = blockchainInfo
//            syncedAmount = blockchainInfo.verificationprogress
//            isRunning = true
//        }
//    }
//    
//    private func handleRPCError(error: String) {
//        if !error.contains("Could not connect to the server") {
//            isRunning = true
//            switch error {
//                // We know these aren't really errors, just standard booting messages.
//            case _ where error.contains("Loading block index"),
//                _ where error.contains("Verifying blocks"),
//                _ where error.contains("Loading P2P addresses…"),
//                _ where error.contains("Pruning"),
//                _ where error.contains("Rewinding"),
//                _ where error.contains("Loading wallet"),
//                _ where error.contains("Shutdown in progress"),
//                _ where error.contains("init message: Starting network threads…"),
//                _ where error.contains("Starting network threads…"):
//                logOutput = error
//                isAnimating = true
//            default:
//                isAnimating = false
//                logOutput = error
//                showMessage(message: error)
//            }
//        } else {
//            isAnimating = false
//            isRunning = false
//            showBitcoinLog()
//            timerForBitcoinStatus.upstream.connect().cancel()
//        }
//    }
//    
//    private func showMessage(message: String) {
//        showError = true
//        self.message = message
//    }
//        
//    func parseScriptResult(script: SCRIPT, result: String) {
//        switch script {
//        case .startBitcoin:
//            showBitcoinLog()
//            
//        case .didBitcoindStart:
//            parseDidBitcoinStart(result: result)
//            
//        default:
//            break
//        }
//    }
//}
//
//#Preview {
//    BitcoinKnots()
//}
