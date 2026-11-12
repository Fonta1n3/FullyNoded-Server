//
//  ExplorerAnalysis.swift
//  FullyNoded-Server
//
//  Reads a whole block or the whole mempool at once, which only makes sense next to the node: a
//  `getblock` verbosity 3 reply is tens of megabytes. Every transaction gets its fee, its age, its
//  categories and a full look for embedded data. Runs off the main thread; no networking or UI.
//

import Foundation

/// One transaction of a block, reduced to what the block's page needs.
struct DigestTx: Identifiable {
    let txid: String
    /// Position in the block.
    let index: Int
    let vsize: Int
    let size: Int
    let feeSats: Int?
    let inputCount: Int
    let outputCount: Int
    let totalOutBtc: Double
    let categories: [String]
    let oldestInputHeight: Int?
    let addresses: [String]
    var isCoinbase: Bool { index == 0 }
    var id: String { txid }

    /// sat/vB. nil: the coinbase, or the node didn't have the block's undo data.
    var feeRate: Double? {
        guard let fee = feeSats, vsize > 0 else { return nil }
        return Double(fee) / Double(vsize)
    }
}

struct ScriptShare: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct BlockDigest {
    let hash: String
    let height: Int
    let time: Int
    let previousHash: String?
    let nextHash: String?
    let confirmations: Int?
    let difficulty: Double?
    let nonce: Int?
    let bits: String?
    let size: Int
    let weight: Int
    let txs: [DigestTx]
    /// For the block map, sorted once here rather than each time it's drawn.
    let txsBySize: [DigestTx]
    let inputCount: Int
    let outputCount: Int
    let totalOutBtc: Double
    let feesSats: Int?
    let subsidySats: Int?
    let miner: String?
    let coinbaseText: String?
    let isSolo: Bool
    let payoutAddress: String?
    /// sat/vB at 10, 25, 50, 75 and 90% of the block's weight. Empty without fees.
    let feePercentiles: [Double]
    let categoryCounts: [(name: String, count: Int)]
    let outputScripts: [ScriptShare]
    let inputScripts: [ScriptShare]
    /// BTC × days since each spent coin was created.
    let coinDaysDestroyed: Double?
    let oldestInput: (height: Int, txid: String)?
    let dataBytes: Int
    let dataByName: [(name: String, bytes: Int, count: Int)]
    let witnessBytes: Int

    /// From `getblock` verbosity 3.
    static func make(block: [String: Any]) -> BlockDigest? {
        guard let hash = RPCValue.string(block["hash"]), let height = RPCValue.int(block["height"]),
              let rawTxs = block["tx"] as? [[String: Any]] else { return nil }
        var txs: [DigestTx] = []
        txs.reserveCapacity(rawTxs.count)
        var categoryCounts: [String: Int] = [:]
        var outScripts: [String: Int] = [:]
        var inScripts: [String: Int] = [:]
        var inputCount = 0, outputCount = 0
        var totalOut = 0.0
        var fees = 0
        var feesKnown = true
        var coinDays = 0.0
        var coinDaysKnown = false
        var oldest: (height: Int, txid: String)?
        var dataBytes = 0
        var dataByName: [String: (bytes: Int, count: Int)] = [:]
        var witnessBytes = 0
        var miner: String?
        var coinbaseText: String?
        var isSolo = false
        var payout: String?
        var coinbaseOut = 0.0

        for (index, raw) in rawTxs.enumerated() {
            guard let tx = ExplorerTx(raw: raw) else { continue }
            let vsize = max(tx.vsize ?? 1, 1)
            let size = tx.size ?? 0
            if let weight = tx.weight, size > 0 { witnessBytes += max(size - (weight - size) / 3, 0) }
            let isCoinbase = index == 0
            if isCoinbase {
                let vin = (raw["vin"] as? [[String: Any]])?.first
                if let hex = RPCValue.string(vin?["coinbase"]) {
                    miner = ExplorerMiner.identify(coinbaseHex: hex)
                    coinbaseText = ExplorerMiner.text(coinbaseHex: hex)
                    isSolo = ExplorerMiner.isSolo(coinbaseHex: hex)
                }
                payout = tx.outputs.first { $0.address != nil && $0.valueBtc > 0 }?.address
                coinbaseOut = tx.totalOutBtc
            } else {
                inputCount += tx.inputs.count
                for input in tx.inputs {
                    inScripts[ExplorerFormat.scriptName(input.scriptType), default: 0] += 1
                    if let source = input.sourceHeight {
                        coinDays += (input.valueBtc ?? 0) * Double(max(height - source, 0)) / 144
                        coinDaysKnown = true
                        if source < (oldest?.height ?? .max) { oldest = (source, tx.txid) }
                    }
                }
            }
            outputCount += tx.outputs.count
            for output in tx.outputs {
                outScripts[ExplorerFormat.scriptName(output.scriptType), default: 0] += 1
            }
            if !isCoinbase { totalOut += tx.totalOutBtc }

            let feeSats = tx.feeBtc.map { Int(($0 * 100_000_000).rounded()) }
            if !isCoinbase {
                if let feeSats = feeSats { fees += feeSats } else { feesKnown = false }
            }
            let embedded = ExplorerEmbeddedData.decode(raw: raw)
            for item in embedded {
                // Every block's coinbase has its witness commitment and such: not what this counts.
                guard !isCoinbase else { continue }
                dataByName[item.name, default: (0, 0)].bytes += item.size
                dataByName[item.name, default: (0, 0)].count += 1
                dataBytes += item.size
            }
            let categories = ExplorerTxCategory.all(tx: tx, embedded: embedded, height: height).map(\.name)
            for name in categories { categoryCounts[name, default: 0] += 1 }
            txs.append(DigestTx(txid: tx.txid, index: index, vsize: vsize, size: size, feeSats: isCoinbase ? nil : feeSats,
                                inputCount: tx.inputs.count, outputCount: tx.outputs.count, totalOutBtc: tx.totalOutBtc,
                                categories: categories,
                                oldestInputHeight: tx.inputs.compactMap(\.sourceHeight).min(),
                                addresses: tx.inputs.compactMap(\.address) + tx.outputs.compactMap(\.address)))
        }

        func shares(_ map: [String: Int]) -> [ScriptShare] {
            map.map { ScriptShare(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        }
        let known = feesKnown && rawTxs.count > 0
        let coinbaseSats = Int((coinbaseOut * 100_000_000).rounded())
        return BlockDigest(hash: hash, height: height, time: RPCValue.int(block["time"]) ?? 0,
                           previousHash: RPCValue.string(block["previousblockhash"]),
                           nextHash: RPCValue.string(block["nextblockhash"]),
                           confirmations: RPCValue.int(block["confirmations"]),
                           difficulty: RPCValue.double(block["difficulty"]),
                           nonce: RPCValue.int(block["nonce"]),
                           bits: RPCValue.string(block["bits"]),
                           size: RPCValue.int(block["size"]) ?? 0,
                           weight: RPCValue.int(block["weight"]) ?? 0,
                           txs: txs, txsBySize: txs.sorted { $0.vsize > $1.vsize }, inputCount: inputCount, outputCount: outputCount, totalOutBtc: totalOut,
                           feesSats: known ? fees : nil,
                           subsidySats: known ? coinbaseSats - fees : nil,
                           miner: miner, coinbaseText: coinbaseText, isSolo: isSolo, payoutAddress: payout,
                           feePercentiles: feePercentiles(txs),
                           categoryCounts: categoryCounts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count },
                           outputScripts: shares(outScripts), inputScripts: shares(inScripts),
                           coinDaysDestroyed: coinDaysKnown ? coinDays : nil,
                           oldestInput: oldest, dataBytes: dataBytes,
                           dataByName: dataByName.map { (name: $0.key, bytes: $0.value.bytes, count: $0.value.count) }.sorted { $0.bytes > $1.bytes },
                           witnessBytes: witnessBytes)
    }

    /// Fee rate at each share of the block's weight, lowest rates first.
    static func feePercentiles(_ txs: [DigestTx]) -> [Double] {
        let paying = txs.compactMap { tx in tx.feeRate.map { (rate: $0, vsize: tx.vsize) } }.sorted { $0.rate < $1.rate }
        let total = paying.reduce(0) { $0 + $1.vsize }
        guard total > 0 else { return [] }
        var result: [Double] = []
        var running = 0
        var targets = [0.1, 0.25, 0.5, 0.75, 0.9]
        for tx in paying {
            running += tx.vsize
            while let target = targets.first, Double(running) >= target * Double(total) {
                result.append(tx.rate)
                targets.removeFirst()
            }
        }
        return result
    }
}

enum ExplorerMempoolRate {
    /// sat/vB, in the order miners take transactions. Core 32's cluster mempool works this out
    /// itself as the rate of the transaction's chunk. Before it: its own rate, less any cheaper
    /// unconfirmed parents it has to wait for.
    static func effective(entry: [String: Any], fees: [String: Any], ownFee: Double, vsize: Int) -> Double {
        if let chunkFee = RPCValue.double(fees["chunk"]), let chunkWeight = RPCValue.double(entry["chunkweight"]), chunkWeight > 0 {
            return chunkFee * 100_000_000 / (chunkWeight / 4)
        }
        let own = ownFee * 100_000_000 / Double(max(vsize, 1))
        if let ancestorFee = RPCValue.double(fees["ancestor"]), let ancestorSize = RPCValue.double(entry["ancestorsize"]), ancestorSize > 0 {
            return min(own, ancestorFee * 100_000_000 / ancestorSize)
        }
        return own
    }
}

/// What the mempool would become if no new transactions arrived: blocks, best payers first.
struct MempoolDigest {
    struct Entry: Identifiable {
        let txid: String
        let vsize: Int
        let feeSats: Int
        /// What miners effectively see (ExplorerMempoolRate).
        let rate: Double
        let time: Int
        var id: String { txid }
    }

    struct ProjectedBlock: Identifiable {
        let index: Int
        let vsize: Int
        let txCount: Int
        let feeSats: Int
        let lowRate: Double
        let highRate: Double
        let medianRate: Double
        var id: Int { index }
    }

    struct Bucket: Identifiable {
        let label: String
        let from: Double
        let vsize: Int
        let count: Int
        var id: String { label }
    }

    static let blockVSize = 1_000_000
    static let bucketEdges: [(from: Double, label: String)] = [
        (0, "<1"), (1, "1"), (2, "2"), (3, "3"), (5, "5"), (8, "8"), (12, "12"), (20, "20"), (35, "35"), (60, "60"), (100, "100+")
    ]

    let count: Int
    let vsize: Int
    let feesSats: Int
    /// nil if this node doesn't say: Core 32's replies no longer do.
    let replaceableCount: Int?
    let oldestTime: Int?
    let blocks: [ProjectedBlock]
    let buckets: [Bucket]
    /// The best-paying few, for a list.
    let top: [Entry]

    /// From `getrawmempool` verbose.
    static func make(pool: [String: Any]) -> MempoolDigest {
        var entries: [Entry] = []
        entries.reserveCapacity(pool.count)
        var replaceable = 0
        var sawSignal = false
        for (txid, value) in pool {
            guard let entry = value as? [String: Any], let fees = entry["fees"] as? [String: Any],
                  let vsize = RPCValue.int(entry["vsize"]), vsize > 0, let base = RPCValue.double(fees["base"]) else { continue }
            let rate = ExplorerMempoolRate.effective(entry: entry, fees: fees, ownFee: base, vsize: vsize)
            let signal = RPCValue.bool(entry["bip125-replaceable"])
            if signal != nil { sawSignal = true }
            if signal == true { replaceable += 1 }
            entries.append(Entry(txid: txid, vsize: vsize, feeSats: Int((base * 100_000_000).rounded()), rate: rate,
                                 time: RPCValue.int(entry["time"]) ?? 0))
        }
        entries.sort { $0.rate > $1.rate }

        var blocks: [ProjectedBlock] = []
        var current: [Entry] = []
        var currentSize = 0
        func flush() {
            guard !current.isEmpty else { return }
            blocks.append(ProjectedBlock(index: blocks.count, vsize: currentSize, txCount: current.count,
                                         feeSats: current.reduce(0) { $0 + $1.feeSats },
                                         lowRate: current.last?.rate ?? 0, highRate: current.first?.rate ?? 0,
                                         medianRate: current[current.count / 2].rate))
            current = []
            currentSize = 0
        }
        for entry in entries {
            if currentSize + entry.vsize > blockVSize { flush() }
            current.append(entry)
            currentSize += entry.vsize
        }
        flush()

        var sizes = [Int](repeating: 0, count: bucketEdges.count)
        var counts = [Int](repeating: 0, count: bucketEdges.count)
        for entry in entries {
            let index = bucketEdges.lastIndex { entry.rate >= $0.from } ?? 0
            sizes[index] += entry.vsize
            counts[index] += 1
        }
        let buckets = bucketEdges.enumerated().map { Bucket(label: $1.label, from: $1.from, vsize: sizes[$0], count: counts[$0]) }
        return MempoolDigest(count: entries.count, vsize: entries.reduce(0) { $0 + $1.vsize },
                             feesSats: entries.reduce(0) { $0 + $1.feeSats }, replaceableCount: sawSignal ? replaceable : nil,
                             oldestTime: entries.map(\.time).filter { $0 > 0 }.min(),
                             blocks: blocks, buckets: buckets, top: Array(entries.prefix(50)))
    }
}

/// How a block that arrived while watching compares with what this node had: only possible
/// by watching the mempool as the block arrives.
struct BlockArrival {
    let txCount: Int
    /// Already in this node's mempool.
    let known: Int
    /// In the block this node would have built, but left out by the miner.
    let leftOut: Int
    /// Share of the template the miner included.
    let templateShare: Double?

    /// A transaction a miner mined without this node having seen it.
    var surprises: Int { txCount - known }
}

/// One transaction in the block being built.
struct TemplateTx {
    let txid: String
    let vsize: Int
    let feeSats: Int
    var feeRate: Double { Double(feeSats) / Double(max(vsize, 1)) }

    static func from(template: [String: Any]) -> [TemplateTx] {
        ((template["transactions"] as? [[String: Any]]) ?? []).compactMap { tx in
            guard let txid = RPCValue.string(tx["txid"]) else { return nil }
            return TemplateTx(txid: txid, vsize: max(((RPCValue.int(tx["weight"]) ?? 4) + 3) / 4, 1), feeSats: RPCValue.int(tx["fee"]) ?? 0)
        }
    }
}
