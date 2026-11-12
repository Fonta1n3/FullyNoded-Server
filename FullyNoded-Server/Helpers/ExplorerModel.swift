//
//  ExplorerModel.swift
//  FullyNoded-Server
//
//  The explorer's state and its calls to the local node. Blocks don't change (until a reorg, see
//  `forget`), so they're kept for as long as the app runs. It only polls while the page is open.
//

import Foundation
import Combine

/// Where the explorer's open on top of its tabs.
enum ExplorerRoute: Hashable {
    case transaction(txid: String, blockhash: String?, highlightedOutput: Int?)
    case analysis(String)
    case address(String)
}

struct ExplorerTip: Equatable {
    let height: Int
    let hash: String
    let pruneHeight: Int?
    let chain: String
    let time: Int?
    let inInitialDownload: Bool
    var isPruned: Bool { pruneHeight != nil }
}

struct ExplorerSoloWin: Identifiable, Equatable {
    let height: Int
    let rewardBtc: Double?
    let miner: String?
    var id: Int { height }
}

enum ExplorerTab: String, CaseIterable, Identifiable {
    case blocks = "Blocks"
    case mempool = "Mempool"
    case chain = "Chain"
    case analyze = "Analyze"
    case famous = "Famous"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .blocks: return "cube"
        case .mempool: return "square.grid.3x3.fill"
        case .chain: return "chart.xyaxis.line"
        case .analyze: return "doc.text.magnifyingglass"
        case .famous: return "star"
        }
    }
}

@MainActor
final class ExplorerModel: ObservableObject {
    static let shared = ExplorerModel()

    @Published var tab: ExplorerTab = .blocks
    @Published var path: [ExplorerRoute] = []
    @Published var tip: ExplorerTip?
    @Published var connectionError: String?
    @Published var selectedHeight: Int?
    @Published private(set) var summaries: [Int: ExplorerBlockSummary] = [:]
    @Published private(set) var template: [TemplateTx] = []
    /// Goes up with each new template, which can have the same number of transactions as the last.
    @Published private(set) var templateRevision = 0
    /// Coin balance checks by title: over a minute each, so kept while the app runs.
    @Published var famousResults: [String: ExplorerScanResult] = [:]
    @Published private(set) var mempoolInfo: [String: Any] = [:]
    @Published private(set) var arrivals: [String: BlockArrival] = [:]
    @Published var soloWin: ExplorerSoloWin?
    /// Height of the block that just arrived, for a moment.
    @Published private(set) var justMined: Int?
    @Published var searchError: String?
    @Published private(set) var isSearching = false
    /// While looking through blocks for a transaction: how far, out of how many.
    @Published private(set) var searchProgress: (done: Int, total: Int)?
    @Published var walletName: String? = UserDefaults.standard.string(forKey: "explorerWallet") {
        didSet { UserDefaults.standard.set(walletName, forKey: "explorerWallet") }
    }
    /// Blocks holding the chosen wallet's coins.
    @Published private(set) var coinHeights = Set<Int>()

    private var digests: [String: BlockDigest] = [:]
    private var digestOrder: [String] = []
    private var digestTasks: [String: Task<BlockDigest, Error>] = [:]
    private var pollTask: Task<Void, Never>?
    private var viewers = 0
    private var wanted: [Int] = []
    private var loading = Set<Int>()
    private var running = 0
    private var mempoolTxids = Set<String>()
    private var searchTask: Task<Void, Never>?
    private var searchNumber = 0
    /// bitcoind's RPC threads are few, and the node has other work.
    private static let maxRunning = 4
    private static let cachedDigests = 12

    // MARK: - Watching

    func startWatching() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.pollOnce(tick: tick)
                tick += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        Task { await refreshCoins() }
    }

    func stopWatching() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        // Blocks arriving while nobody's watching can't be compared with what the node had then.
        forgetMempool()
    }

    private func forgetMempool() {
        mempoolTxids = []
        template = []
        templateRevision += 1
    }

    private func pollOnce(tick: Int) async {
        do {
            let new = try await fetchTip()
            connectionError = nil
            let old = tip
            let changed = old?.hash != new.hash
            tip = new
            if old?.chain != new.chain { reset() }
            if changed {
                if let old = old, old.chain == new.chain {
                    await received(new, from: old)
                } else {
                    selectedHeight = selectedHeight ?? new.height
                }
            }
            // A few seconds apart so a block never finds the mempool list stale, the rest less often.
            if changed || tick % 4 == 0 { await refreshMempool() }
            if changed || tick % 7 == 0 { await refreshTemplate() }
        } catch let error as ExplorerError {
            connectionError = error.message
            forgetMempool()
        } catch {
            connectionError = error.localizedDescription
            forgetMempool()
        }
    }

    private func reset() {
        summaries = [:]
        digests = [:]
        digestOrder = []
        arrivals = [:]
        coinHeights = []
        famousResults = [:]
        selectedHeight = nil
        forgetMempool()
        path = []
    }

    func fetchTip() async throws -> ExplorerTip {
        let response = try await ExplorerRPC.call("getblockchaininfo", timeout: 15)
        guard let info = response as? [String: Any], let height = RPCValue.int(info["blocks"]), let hash = RPCValue.string(info["bestblockhash"]) else {
            throw ExplorerError("Your node isn't ready yet.")
        }
        let pruned = RPCValue.bool(info["pruned"]) == true
        return ExplorerTip(height: height, hash: hash, pruneHeight: pruned ? RPCValue.int(info["pruneheight"]) : nil,
                           chain: RPCValue.string(info["chain"]) ?? "main", time: RPCValue.int(info["time"]),
                           inInitialDownload: RPCValue.bool(info["initialblockdownload"]) == true)
    }

    private func received(_ new: ExplorerTip, from old: ExplorerTip) async {
        // A block we were showing no longer in the chain: a reorg.
        if let oldHash = summaries[old.height]?.hash ?? Optional(old.hash),
           new.height >= old.height,
           let same = try? await ExplorerRPC.call("getblockhash", ["height": old.height]) as? String, same != oldHash {
            forget(from: max(old.height - 12, 0))
        } else if new.height < old.height {
            forget(from: new.height)
        }
        let followingTip = selectedHeight == old.height || selectedHeight == nil
        if followingTip { selectedHeight = new.height }
        guard new.height > old.height else { return }
        Task { await refreshCoins() }
        justMined = new.height
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.justMined = nil
        }
        // Only ever about one a block, unless the node's catching up.
        guard new.height - old.height <= 3 else { return }
        for height in (old.height + 1)...new.height { await noteArrival(height) }
    }

    /// Compares a new block with this node's mempool and next block from just before it, and
    /// checks if it's a solo win.
    private func noteArrival(_ height: Int) async {
        guard let hash = try? await ExplorerRPC.call("getblockhash", ["height": height]) as? String,
              let block = try? await ExplorerRPC.call("getblock", ["blockhash": hash, "verbosity": 1]) as? [String: Any] else { return }
        let txids = (block["tx"] as? [Any])?.compactMap { RPCValue.string($0) } ?? []
        if txids.count > 1, !mempoolTxids.isEmpty {
            let inBlock = Set(txids)
            let others = txids.dropFirst()
            let known = others.filter { mempoolTxids.contains($0) }.count
            let leftOut = template.filter { !inBlock.contains($0.txid) }.count
            let share: Double? = template.isEmpty ? nil : Double(template.count - leftOut) / Double(template.count)
            arrivals[hash] = BlockArrival(txCount: others.count, known: known, leftOut: leftOut, templateShare: share)
        }
        let summary = await loadSummary(height, block: block)
        if let summary = summary {
            summaries[height] = summary
            if summary.isSolo {
                soloWin = ExplorerSoloWin(height: height, rewardBtc: summary.rewardBtc, miner: summary.miner)
            }
        }
    }

    private func refreshMempool() async {
        if let info = try? await ExplorerRPC.call("getmempoolinfo", timeout: 15) as? [String: Any] { mempoolInfo = info }
        if let ids = try? await ExplorerRPC.call("getrawmempool", ["verbose": false], timeout: 30) as? [Any] {
            let set = await Task.detached { Set(ids.compactMap { $0 as? String }) }.value
            mempoolTxids = set
        }
    }

    func refreshTemplate() async {
        var rules = ["segwit"]
        if tip?.chain == "signet" { rules.append("signet") }
        guard let response = try? await ExplorerRPC.call("getblocktemplate", ["template_request": ["rules": rules]], timeout: 30) as? [String: Any] else { return }
        template = await Task.detached { TemplateTx.from(template: response) }.value
        templateRevision += 1
    }

    // MARK: - Block summaries

    func requestSummary(_ height: Int) {
        guard height >= 0, summaries[height] == nil, !loading.contains(height), !wanted.contains(height) else { return }
        wanted.append(height)
        drain()
    }

    private func drain() {
        while running < Self.maxRunning, let height = wanted.popLast() {
            running += 1
            loading.insert(height)
            Task { [weak self] in
                let summary = await self?.loadSummary(height)
                guard let self = self else { return }
                self.running -= 1
                self.loading.remove(height)
                if let summary = summary { self.summaries[height] = summary }
                self.drain()
            }
        }
    }

    /// Stats if the node has the block's undo data, otherwise just the header (which a pruned node
    /// always keeps). Then the coinbase, if the block's still there. `block`: its `getblock`
    /// verbosity 1 reply, if the caller has it already.
    private func loadSummary(_ height: Int, block: [String: Any]? = nil) async -> ExplorerBlockSummary? {
        var summary: ExplorerBlockSummary?
        if let stats = try? await ExplorerRPC.call("getblockstats", ["hash_or_height": height, "stats": ExplorerBlockSummary.statNames]) as? [String: Any] {
            summary = ExplorerBlockSummary(stats: stats)
        }
        if summary == nil {
            guard let hash = try? await ExplorerRPC.call("getblockhash", ["height": height]) as? String,
                  let header = try? await ExplorerRPC.call("getblockheader", ["blockhash": hash]) as? [String: Any] else { return nil }
            summary = ExplorerBlockSummary(header: header)
        }
        if let hash = summary?.hash, let hex = await coinbaseHex(blockhash: hash, block: RPCValue.string(block?["hash"]) == hash ? block : nil) {
            summary?.miner = ExplorerMiner.identify(coinbaseHex: hex)
            summary?.isSolo = ExplorerMiner.isSolo(coinbaseHex: hex)
        }
        return summary
    }

    /// Core 29+ puts the coinbase in the block's reply; older nodes need one more small call.
    func coinbaseHex(blockhash: String, block fetched: [String: Any]? = nil) async -> String? {
        var block = fetched
        if block == nil { block = try? await ExplorerRPC.call("getblock", ["blockhash": blockhash, "verbosity": 1]) as? [String: Any] }
        guard let block = block else { return nil }
        if let hex = RPCValue.string((block["coinbase_tx"] as? [String: Any])?["coinbase"]) { return hex }
        guard let first = (block["tx"] as? [Any])?.first.flatMap({ RPCValue.string($0) }),
              let raw = try? await ExplorerRPC.call("getrawtransaction", ["txid": first, "verbosity": 1, "blockhash": blockhash]) as? [String: Any] else { return nil }
        return RPCValue.string((raw["vin"] as? [[String: Any]])?.first?["coinbase"])
    }

    /// After a reorg: everything from this height up may be different.
    func forget(from height: Int) {
        for key in summaries.keys where key >= height {
            if let hash = summaries[key]?.hash {
                digests[hash] = nil
                arrivals[hash] = nil
            }
            summaries[key] = nil
        }
        digestOrder.removeAll { digests[$0] == nil }
    }

    func blockHash(height: Int) async throws -> String {
        if let hash = summaries[height]?.hash { return hash }
        guard let hash = try await ExplorerRPC.call("getblockhash", ["height": height]) as? String else {
            throw ExplorerError("No block at that height.")
        }
        return hash
    }

    /// The whole block, read and analysed. nil data for a pruned one throws Core's message.
    func digest(hash: String) async throws -> BlockDigest {
        if let cached = digests[hash] { return cached }
        if let task = digestTasks[hash] { return try await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> BlockDigest in
            guard let block = try await ExplorerRPC.call("getblock", ["blockhash": hash, "verbosity": 3], timeout: 300) as? [String: Any],
                  let digest = BlockDigest.make(block: block) else {
                throw ExplorerError("The node couldn't read that block.")
            }
            return digest
        }
        digestTasks[hash] = task
        defer { digestTasks[hash] = nil }
        let digest = try await task.value
        digests[hash] = digest
        digestOrder.append(hash)
        while digestOrder.count > Self.cachedDigests { digests[digestOrder.removeFirst()] = nil }
        return digest
    }

    func hasDigest(hash: String) -> Bool { digests[hash] != nil }

    func show(height: Int) {
        tab = .blocks
        path = []
        selectedHeight = height
    }

    func open(_ route: ExplorerRoute) { path.append(route) }

    // MARK: - Search

    /// Anything someone might paste: a height, a block hash, a txid, an address, a raw transaction
    /// or a PSBT.
    func search(_ text: String) {
        // None of these contain spaces, and a pasted PSBT or transaction is often wrapped.
        let query = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !query.isEmpty else { return }
        searchError = nil
        searchTask?.cancel()
        searchNumber += 1
        let number = searchNumber
        isSearching = true
        searchTask = Task { [weak self] in
            await self?.resolve(query)
            // A search that was replaced mustn't clear the state of the one that replaced it.
            guard let self = self, self.searchNumber == number else { return }
            self.isSearching = false
            self.searchProgress = nil
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchNumber += 1
        isSearching = false
        searchProgress = nil
    }

    private func resolve(_ query: String) async {
        let digits = query.replacingOccurrences(of: ",", with: "")
        if let height = Int(digits), height >= 0 {
            if let tip = tip, height > tip.height {
                searchError = "This node's chain only reaches block \(tip.height.withCommas)."
            } else {
                show(height: height)
            }
            return
        }
        let isHex = query.allSatisfy(\.isHexDigit)
        if isHex, query.count == 64 {
            let lower = query.lowercased()
            if let header = try? await ExplorerRPC.call("getblockheader", ["blockhash": lower]) as? [String: Any], let height = RPCValue.int(header["height"]) {
                show(height: height)
                return
            }
            await findTransaction(lower)
            return
        }
        if query.hasPrefix("cHNidP") || (isHex && query.count > 64) {
            path.append(.analysis(query))
            return
        }
        if let check = try? await ExplorerRPC.call("validateaddress", ["address": query]) as? [String: Any], check["isvalid"] as? Bool == true {
            path.append(.address(query))
            return
        }
        searchError = "That isn't a block height, block hash, transaction ID, address, raw transaction or PSBT on this network."
    }

    /// In the mempool, in txindex, or else block by block from the tip: without txindex that's the
    /// only way, and a local node can do it.
    private func findTransaction(_ txid: String) async {
        if (try? await ExplorerRPC.call("getrawtransaction", ["txid": txid, "verbosity": 1]) as? [String: Any]) != nil {
            guard !Task.isCancelled else { return }
            path.append(.transaction(txid: txid, blockhash: nil, highlightedOutput: nil))
            return
        }
        guard let tip = tip else { return }
        let lowest = tip.pruneHeight ?? 0
        let total = tip.height - lowest + 1
        var height = tip.height
        while height >= lowest {
            if Task.isCancelled { return }
            searchProgress = (tip.height - height, total)
            guard let hash = try? await ExplorerRPC.call("getblockhash", ["height": height]) as? String,
                  let block = try? await ExplorerRPC.call("getblock", ["blockhash": hash, "verbosity": 1], timeout: 60) as? [String: Any] else { break }
            if ((block["tx"] as? [Any]) ?? []).contains(where: { ($0 as? String) == txid }) {
                path.append(.transaction(txid: txid, blockhash: hash, highlightedOutput: nil))
                return
            }
            height -= 1
        }
        guard !Task.isCancelled else { return }
        searchError = tip.isPruned
            ? "It isn't in your mempool or any block your node still has (back to \(lowest.withCommas))."
            : "It isn't in your mempool or any block."
    }

    // MARK: - Transactions

    /// A transaction by its txid, with what its inputs spend. Finds the block by looking if needed.
    func transaction(txid: String, blockhash: String?) async throws -> [String: Any] {
        var params: [String: Any] = ["txid": txid, "verbosity": 2]
        if let blockhash = blockhash { params["blockhash"] = blockhash }
        do {
            guard let raw = try await ExplorerRPC.call("getrawtransaction", params) as? [String: Any] else {
                throw ExplorerError("The node couldn't find that transaction.")
            }
            return raw
        } catch let error as ExplorerError where error.code == -5 {
            throw ExplorerError("Your node doesn't have this transaction. Without txindex, it needs the block it's in: search for its txid to look through your node's blocks.")
        }
    }

    /// What a decoded or unconfirmed transaction's reply leaves out: each input from the chain's
    /// UTXO set, or from its parent if that's unconfirmed too. Whatever can't be found stays unknown.
    func fillInputs(_ tx: ExplorerTx, tipHeight: Int?) async -> ExplorerTx {
        guard !tx.inputsKnown, let tipHeight = tipHeight else { return tx }
        var filled = tx
        await withTaskGroup(of: (Int, Double?, String?, String?, Int?).self) { group in
            var active = 0
            for (index, input) in tx.inputs.enumerated() where !input.coinbase && input.valueBtc == nil {
                guard let txid = input.txid, let vout = input.vout else { continue }
                if active >= 8, let result = await group.next() {
                    apply(result, to: &filled)
                    active -= 1
                }
                active += 1
                group.addTask {
                    if let out = try? await ExplorerRPC.call("gettxout", ["txid": txid, "n": vout, "include_mempool": false]) as? [String: Any] {
                        let script = out["scriptPubKey"] as? [String: Any]
                        // The tip's height minus its confirmations gives the block it was created in.
                        let height = RPCValue.int(out["confirmations"]).map { tipHeight - $0 + 1 }
                        return (index, RPCValue.double(out["value"]), RPCValue.string(script?["address"]), RPCValue.string(script?["type"]), height)
                    }
                    // Spent or unconfirmed: its parent, in the mempool or txindex.
                    if let parent = try? await ExplorerRPC.call("getrawtransaction", ["txid": txid, "verbosity": 1]) as? [String: Any],
                       let output = ExplorerTx(raw: parent)?.outputs.first(where: { $0.n == vout }) {
                        return (index, output.valueBtc, output.address, output.scriptType, nil)
                    }
                    return (index, nil, nil, nil, nil)
                }
            }
            for await result in group { apply(result, to: &filled) }
        }
        if filled.feeBtc == nil, filled.inputsKnown {
            filled.feeBtc = filled.inputs.reduce(0) { $0 + ($1.valueBtc ?? 0) } - filled.totalOutBtc
        }
        return filled
    }

    private func apply(_ result: (Int, Double?, String?, String?, Int?), to tx: inout ExplorerTx) {
        tx.inputs[result.0].valueBtc = result.1
        tx.inputs[result.0].address = result.2
        tx.inputs[result.0].scriptType = result.3
        tx.inputs[result.0].sourceHeight = result.4
    }

    enum OutputStatus: Equatable {
        case unspent
        case spentInMempool(by: String)
        case spent
    }

    func outputStatus(txid: String, n: Int) async -> OutputStatus? {
        guard let response = try? await ExplorerRPC.call("gettxout", ["txid": txid, "n": n]) else { return nil }
        if response is [String: Any] { return .unspent }
        if let rows = try? await ExplorerRPC.call("gettxspendingprevout", ["outputs": [["txid": txid, "vout": n]]]) as? [[String: Any]],
           let spender = rows.first.flatMap({ RPCValue.string($0["spendingtxid"]) }) {
            return .spentInMempool(by: spender)
        }
        return .spent
    }

    struct Spender: Equatable {
        let txid: String
        let blockhash: String
        let height: Int
        let input: Int
    }

    /// Core keeps no index of spends, but the spend's outpoint is 36 fixed bytes in the block's raw
    /// data, so it can be looked for directly, far faster than decoding: a block takes milliseconds.
    /// nil if not found in the blocks this node still has.
    nonisolated func findSpender(txid: String, vout: Int, from start: Int, to end: Int,
                                 progress: @escaping @Sendable (Int) async -> Void) async throws -> Spender? {
        guard let reversed = Hex.decode(txid).map({ Hex.encode($0.reversed()) }) else { return nil }
        let little = withUnsafeBytes(of: UInt32(vout).littleEndian) { Hex.encode($0) }
        let pattern = Data((reversed + little).utf8)
        var height = start
        while height <= end {
            try Task.checkCancellation()
            await progress(height)
            guard let hash = try await ExplorerRPC.call("getblockhash", ["height": height]) as? String,
                  let hex = try await ExplorerRPC.call("getblock", ["blockhash": hash, "verbosity": 0], timeout: 60) as? String else { return nil }
            if Data(hex.utf8).range(of: pattern) != nil,
               let block = try await ExplorerRPC.call("getblock", ["blockhash": hash, "verbosity": 2], timeout: 120) as? [String: Any] {
                // Confirm it's really that input, not the same bytes by chance.
                for tx in block["tx"] as? [[String: Any]] ?? [] {
                    for (index, input) in (tx["vin"] as? [[String: Any]] ?? []).enumerated()
                    where input["txid"] as? String == txid && RPCValue.int(input["vout"]) == vout {
                        if let spender = tx["txid"] as? String {
                            return Spender(txid: spender, blockhash: hash, height: height, input: index)
                        }
                    }
                }
            }
            height += 1
        }
        return nil
    }

    // MARK: - UTXO scans

    /// Runs a whole-UTXO-set scan, reporting progress in percent. Works on a pruned node. A node
    /// runs one at a time, and it can take a minute or more.
    nonisolated func scan(_ objects: [Any], progress: @escaping @Sendable (Double) async -> Void) async throws -> ExplorerScanResult {
        let poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let status = try? await ExplorerRPC.call("scantxoutset", ["action": "status"]) as? [String: Any],
                   let percent = RPCValue.double(status["progress"]) {
                    await progress(percent)
                }
            }
        }
        defer { poll.cancel() }
        let response: Any
        do {
            response = try await withTaskCancellationHandler {
                try await ExplorerRPC.call("scantxoutset", ["action": "start", "scanobjects": objects], timeout: 1800)
            } onCancel: {
                Task { _ = try? await ExplorerRPC.call("scantxoutset", ["action": "abort"]) }
            }
        } catch let error as ExplorerError where error.code == -8 {
            throw ExplorerError("Your node is already scanning its UTXO set. Try again when that's done.")
        }
        guard let dict = response as? [String: Any], let result = ExplorerScanResult(response: dict) else {
            throw ExplorerError("The scan didn't finish.")
        }
        return result
    }

    // MARK: - Wallets

    func loadedWallets() async -> [String] {
        ((try? await ExplorerRPC.call("listwallets")) as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// A wallet's coins by block. Heights come from counting back from the tip, so a block arriving
    /// mid-way would put every coin one off: if the tip moves, ask again.
    func walletCoins(wallet: String) async throws -> [ExplorerCoinBlock] {
        for attempt in 0..<3 {
            let before = try await fetchTip()
            guard let utxos = try await ExplorerRPC.call("listunspent", ["minconf": 0, "include_immature_coinbase": true], wallet: wallet) as? [[String: Any]] else {
                throw ExplorerError("Your node didn't answer.")
            }
            let after = try await fetchTip()
            if after.hash == before.hash || attempt == 2 {
                return ExplorerCoinBlock.group(utxos: utxos, tipHeight: before.height)
            }
        }
        return []
    }

    func refreshCoins() async {
        guard let wallet = walletName, let groups = try? await walletCoins(wallet: wallet) else {
            coinHeights = []
            return
        }
        coinHeights = Set(groups.compactMap(\.height))
    }

    // MARK: - Chain

    /// Summaries for a run of blocks, kept as they arrive. Skips what the node can't read, and asks
    /// for no more once its task is cancelled.
    func summaries(heights: [Int]) async -> [ExplorerBlockSummary] {
        var missing = heights.filter { summaries[$0] == nil }
        await withTaskGroup(of: ExplorerBlockSummary?.self) { group in
            var active = 0
            while !Task.isCancelled, let height = missing.popLast() {
                if active >= Self.maxRunning, let summary = await group.next() {
                    if let summary = summary { summaries[summary.height] = summary }
                    active -= 1
                }
                active += 1
                group.addTask { [weak self] in await self?.loadSummary(height) }
            }
            for await summary in group {
                if let summary = summary { summaries[summary.height] = summary }
            }
        }
        return heights.compactMap { summaries[$0] }
    }
}
