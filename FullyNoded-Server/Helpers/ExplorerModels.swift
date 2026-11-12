//
//  ExplorerModels.swift
//  FullyNoded-Server
//
//  What the block explorer shows, read leniently from the node's replies: Core's fields vary by
//  version, and on a pruned node anything that needs a block's data can be missing. No networking
//  and no UI here.
//

import Foundation

enum RPCValue {
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string) ?? Double(string).map { Int($0) }
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: return number.boolValue
        default: return nil
        }
    }
}

enum Hex {
    static func decode(_ hex: String) -> Data? { SPHex.decode(hex) }
    static func encode<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { SPHex.encode(Data(bytes)) }
}

enum ExplorerFormat {
    static func btc(_ value: Double) -> String { String(format: "%.8f BTC", value) }

    static func btc(sats: Int) -> String { btc(Double(sats) / 100_000_000) }

    /// For small spaces: "3.15 BTC".
    static func btcShort(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f BTC", value) : String(format: "%.3f BTC", value)
    }

    static func feeRate(_ rate: Double) -> String {
        rate >= 10 ? "\(Int(rate.rounded())) sat/vB" : String(format: "%.1f sat/vB", rate)
    }

    /// "12m ago", "1h 59m ago", "2d 5h ago", "3y 20d ago": the two largest units. Never seconds:
    /// a block's time is only what its miner wrote, often minutes out.
    static func ago(_ time: Int, now: Date = Date()) -> String {
        let minutes = Int(max(now.timeIntervalSince1970 - TimeInterval(time), 0)) / 60
        guard minutes >= 1 else { return "just now" }
        let hours = minutes / 60
        let days = hours / 24
        let years = days / 365
        func pair(_ big: Int, _ bigUnit: String, _ small: Int, _ smallUnit: String) -> String {
            small > 0 ? "\(big)\(bigUnit) \(small)\(smallUnit) ago" : "\(big)\(bigUnit) ago"
        }
        if years > 0 { return pair(years, "y", days % 365, "d") }
        if days > 0 { return pair(days, "d", hours % 24, "h") }
        if hours > 0 { return pair(hours, "h", minutes % 60, "m") }
        return "\(minutes)m ago"
    }

    /// Time left until the usual spacing after the last block has passed: "~7m", then "any
    /// moment". A guide only: blocks are found at random, and one is never really "due".
    static func eta(lastBlockTime time: Int, spacing: TimeInterval = 600, now: Date = Date()) -> String {
        let remaining = min(TimeInterval(time) + spacing - now.timeIntervalSince1970, spacing)
        guard remaining > 0 else { return "any moment" }
        return remaining < 60 ? "<1m" : "~\(Int((remaining / 60).rounded(.up)))m"
    }

    /// Always in megabytes, with enough places that a small transaction doesn't read as zero.
    static func megabytes(_ bytes: Int) -> String {
        let value = Double(bytes) / 1_000_000
        return String(format: value >= 0.01 ? "%.3f MB" : "%.5f MB", value)
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
    }

    static func date(_ time: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(time)).formatted(date: .abbreviated, time: .shortened)
    }

    static func shortTxid(_ txid: String) -> String { "\(txid.prefix(10))…\(txid.suffix(10))" }

    /// How old in words, from a number of blocks: "about 6 years".
    static func age(blocks: Int) -> String {
        if blocks < 144 { return "\(blocks) block\(blocks == 1 ? "" : "s")" }
        if blocks < 4_320 { return "about \(blocks / 144) day\(blocks / 144 == 1 ? "" : "s")" }
        if blocks < 52_560 { return "about \(blocks / 4_320) month\(blocks / 4_320 == 1 ? "" : "s")" }
        return "about \(blocks / 52_560) year\(blocks / 52_560 == 1 ? "" : "s")"
    }

    static func hashrate(_ value: Double) -> String {
        let units: [(Double, String)] = [(1e18, "EH/s"), (1e15, "PH/s"), (1e12, "TH/s"), (1e9, "GH/s"), (1e6, "MH/s"), (1e3, "kH/s")]
        for (scale, unit) in units where value >= scale {
            return String(format: "%.1f %@", value / scale, unit)
        }
        return String(format: "%.0f H/s", value)
    }

    static func scriptName(_ type: String?) -> String {
        switch type {
        case "nulldata": return "OP_RETURN"
        case "multisig": return "Bare multisig"
        case "pubkey": return "P2PK"
        case "pubkeyhash": return "P2PKH"
        case "scripthash": return "P2SH"
        case "witness_v0_keyhash": return "P2WPKH"
        case "witness_v0_scripthash": return "P2WSH"
        case "witness_v1_taproot": return "Taproot"
        case "anchor": return "Anchor"
        case "witness_unknown": return "Unknown witness"
        case "nonstandard": return "Non-standard"
        case let other?: return other
        case nil: return "Unknown"
        }
    }
}

/// One block in the strip. Stats are nil when the node can't compute them (a pruned block, or
/// the genesis block), and then only the header's facts are known.
struct ExplorerBlockSummary: Equatable {
    let height: Int
    let hash: String?
    let time: Int
    let txCount: Int
    /// Both from getblockstats, which leaves out the coinbase: a block's true figures are a little more.
    let weight: Int?
    let size: Int?
    let totalFeeSats: Int?
    let subsidySats: Int?
    /// sat/vB at the 10th, 25th, 50th, 75th and 90th percentile of weight.
    let feeRatePercentiles: [Int]?
    /// From the coinbase.
    var miner: String? = nil
    var isSolo = false

    static let statNames = ["height", "blockhash", "time", "txs", "total_weight", "total_size", "totalfee", "subsidy", "feerate_percentiles"]
    static let maxWeight = 4_000_000

    /// What the miner earned: new coins plus fees.
    var rewardBtc: Double? {
        guard let subsidy = subsidySats, let fees = totalFeeSats else { return nil }
        return Double(subsidy + fees) / 100_000_000
    }

    var medianFeeRate: Int? {
        guard let rates = feeRatePercentiles, rates.count == 5 else { return nil }
        return rates[2]
    }

    /// How full the block is, 0...1.
    var fullness: Double? {
        weight.map { min(Double($0) / Double(Self.maxWeight), 1) }
    }

    init?(stats: [String: Any]) {
        guard let height = RPCValue.int(stats["height"]), let time = RPCValue.int(stats["time"]), let txs = RPCValue.int(stats["txs"]) else { return nil }
        self.height = height
        hash = RPCValue.string(stats["blockhash"])
        self.time = time
        txCount = txs
        weight = RPCValue.int(stats["total_weight"])
        size = RPCValue.int(stats["total_size"])
        totalFeeSats = RPCValue.int(stats["totalfee"])
        subsidySats = RPCValue.int(stats["subsidy"])
        feeRatePercentiles = (stats["feerate_percentiles"] as? [Any])?.compactMap { RPCValue.int($0) }
    }

    init?(header: [String: Any]) {
        guard let height = RPCValue.int(header["height"]), let time = RPCValue.int(header["time"]) else { return nil }
        self.height = height
        hash = RPCValue.string(header["hash"])
        self.time = time
        txCount = RPCValue.int(header["nTx"]) ?? 0
        weight = nil
        size = nil
        totalFeeSats = nil
        subsidySats = nil
        feeRatePercentiles = nil
    }
}

/// A transaction with what each input spends: `getrawtransaction` verbosity 2, `getblock`
/// verbosity 3's entries, or a decoded raw transaction with its inputs filled in afterwards.
struct ExplorerTx {
    struct Input {
        let txid: String?
        let vout: Int?
        let coinbase: Bool
        var valueBtc: Double?
        var address: String?
        var scriptType: String?
        /// The block the spent output was created in, which is how tracing finds it without txindex.
        var sourceHeight: Int?
        let sequence: Int?
    }

    struct Output {
        let n: Int
        let valueBtc: Double
        let address: String?
        let scriptType: String?
    }

    let txid: String
    let vsize: Int?
    let weight: Int?
    let size: Int?
    let locktime: Int?
    let version: Int?
    var feeBtc: Double?
    let blockhash: String?
    let blocktime: Int?
    let confirmations: Int
    var inputs: [Input]
    let outputs: [Output]

    var totalOutBtc: Double { outputs.reduce(0) { $0 + $1.valueBtc } }

    /// sat/vB.
    var feeRate: Double? {
        guard let fee = feeBtc, let vsize = vsize, vsize > 0 else { return nil }
        return fee * 100_000_000 / Double(vsize)
    }

    var isCoinbase: Bool { inputs.first?.coinbase == true }

    /// Replaceable if any input opts in (BIP125).
    var signalsRBF: Bool { inputs.contains { ($0.sequence ?? .max) < 0xFFFFFFFE } }

    /// Whether every input's value is known, so its fee can be worked out.
    var inputsKnown: Bool { !inputs.contains { !$0.coinbase && $0.valueBtc == nil } }

    init?(raw: [String: Any]) {
        guard let txid = RPCValue.string(raw["txid"]) else { return nil }
        self.txid = txid
        vsize = RPCValue.int(raw["vsize"])
        weight = RPCValue.int(raw["weight"])
        size = RPCValue.int(raw["size"])
        locktime = RPCValue.int(raw["locktime"])
        version = RPCValue.int(raw["version"])
        feeBtc = RPCValue.double(raw["fee"])
        blockhash = RPCValue.string(raw["blockhash"])
        blocktime = RPCValue.int(raw["blocktime"])
        confirmations = RPCValue.int(raw["confirmations"]) ?? 0
        inputs = ((raw["vin"] as? [[String: Any]]) ?? []).map { vin in
            let prevout = vin["prevout"] as? [String: Any]
            let script = prevout?["scriptPubKey"] as? [String: Any]
            return Input(txid: RPCValue.string(vin["txid"]),
                         vout: RPCValue.int(vin["vout"]),
                         coinbase: vin["coinbase"] != nil,
                         valueBtc: RPCValue.double(prevout?["value"]),
                         address: RPCValue.string(script?["address"]),
                         scriptType: RPCValue.string(script?["type"]),
                         sourceHeight: RPCValue.int(prevout?["height"]),
                         sequence: RPCValue.int(vin["sequence"]))
        }
        outputs = ((raw["vout"] as? [[String: Any]]) ?? []).enumerated().map { index, vout in
            let script = vout["scriptPubKey"] as? [String: Any]
            return Output(n: RPCValue.int(vout["n"]) ?? index,
                          valueBtc: RPCValue.double(vout["value"]) ?? 0,
                          address: RPCValue.string(script?["address"]),
                          scriptType: RPCValue.string(script?["type"]))
        }
    }
}

/// Who mined a block, from the text miners put in the coinbase. Self-reported, and anyone can
/// write anything there.
enum ExplorerMiner {
    /// Text to find in the coinbase, and the pool's name.
    private static let knownPools: [(tag: String, name: String)] = [
        ("solo.ckpool", "CKPool Solo"), ("foundry", "Foundry USA"), ("antpool", "AntPool"), ("viabtc", "ViaBTC"), ("f2pool", "F2Pool"),
        ("spiderpool", "SpiderPool"), ("mara", "MARA Pool"), ("luxor", "Luxor"), ("ocean", "OCEAN"),
        ("sbicrypto", "SBI Crypto"), ("binance", "Binance Pool"), ("secpool", "SECPOOL"), ("braiins", "Braiins"),
        ("slush", "Braiins"), ("poolin", "Poolin"), ("whitepool", "WhitePool"), ("titan", "Titan"),
        ("miningsquared", "Mining Squared"), ("1thash", "1THash"), ("kucoin", "KuCoin Pool"),
        ("btc.com", "BTC.com"), ("bitfufu", "BitFuFu"), ("nicehash", "NiceHash"), ("pyblock", "PyBLOCK"),
        ("public-pool", "Public Pool"), ("ckpool", "CKPool"), ("solo", "Solo miner")
    ]

    /// Whether the coinbase says it's a solo win: one small miner taking a whole block reward, not
    /// a share of a pool's. Self-reported like any tag. "solo" must be a word of its own, so a
    /// name that merely contains it doesn't count.
    static func isSolo(coinbaseHex: String) -> Bool {
        guard let bytes = Hex.decode(coinbaseHex) else { return false }
        let text = bytes.split { $0 < 0x20 || $0 > 0x7E }
            .map { String(decoding: $0, as: UTF8.self) }.joined(separator: " ").lowercased()
        if ["solo.ckpool", "public-pool", "publicpool", "public pool"].contains(where: text.contains) { return true }
        return text.range(of: #"(^|[^a-z0-9])solo([^a-z0-9]|$)"#, options: .regularExpression) != nil
    }

    /// The pool's name if recognised, otherwise the longest text in the coinbase script's hex.
    static func identify(coinbaseHex: String) -> String? {
        guard let bytes = Hex.decode(coinbaseHex) else { return nil }
        // Runs of printable text; the rest of the script is numbers.
        let runs = bytes.split { $0 < 0x20 || $0 > 0x7E }
            .map { String(decoding: $0, as: UTF8.self) }
            .filter { $0.count >= 4 && $0.filter(\.isLetter).count >= 3 }
        let text = runs.joined(separator: " ").lowercased()
        if let pool = knownPools.first(where: { text.contains($0.tag) }) { return pool.name }
        return runs.max { $0.count < $1.count }.map { String($0.prefix(24)) }
    }

    /// All the readable text in a coinbase, for reading in full.
    static func text(coinbaseHex: String) -> String? {
        guard let bytes = Hex.decode(coinbaseHex) else { return nil }
        let runs = bytes.split { $0 < 0x20 || $0 > 0x7E }.map { String(decoding: $0, as: UTF8.self) }.filter { $0.count >= 3 }
        return runs.isEmpty ? nil : runs.joined(separator: " ")
    }
}

/// What kind of transaction this looks like. All of these are guesses from public data: a payment
/// can look like a consolidation, and nothing on-chain proves who owns an address.
struct ExplorerTxCategory: Equatable {
    let name: String
    let detail: String

    static let years5Blocks = 262_800
    static let blocksPerYear = 52_560
    /// The first subsidy era ended here, in late 2012.
    static let firstEraEnd = 210_000
    static let dataName = "Data/spam"
    static let veryOldName = "Very old coins"
    static let oldName = "Old coins"
    static let backToSenderName = "Address reuse"

    /// From inputs and outputs alone.
    static func shape(inputs: Int, outputValues: [Double]) -> ExplorerTxCategory? {
        let outputs = outputValues.count
        guard inputs > 0, outputs > 0 else { return nil }
        // The same amount to several outputs, from several inputs: what makes outputs unlinkable.
        var counts: [Int: Int] = [:]
        for value in outputValues where value > 0 { counts[Int((value * 100_000_000).rounded()), default: 0] += 1 }
        let equal = counts.values.max() ?? 0
        if equal >= 3, inputs >= 3 {
            return ExplorerTxCategory(name: "CoinJoin", detail: "\(equal) outputs of the same amount, from \(inputs) inputs. Likely a CoinJoin.")
        }
        if (inputs >= 5 && outputs <= 2) || (inputs >= 3 && outputs == 1) {
            return ExplorerTxCategory(name: "Consolidation", detail: "\(inputs) inputs into \(outputs) output\(outputs == 1 ? "" : "s"). Likely merging coins.")
        }
        if outputs >= 10 {
            return ExplorerTxCategory(name: "Batch payment", detail: "One transaction paying \(outputs) outputs.")
        }
        if outputs == 1 {
            return ExplorerTxCategory(name: "No change", detail: "Everything went to one output: a sweep, or a move between someone's own wallets.")
        }
        return nil
    }

    /// Everything known about a transaction. `height`: the block it's in, or the next one while
    /// it's in the mempool.
    static func all(tx: ExplorerTx, embedded: [ExplorerEmbeddedData], height: Int?) -> [ExplorerTxCategory] {
        var categories: [ExplorerTxCategory] = []
        if !tx.isCoinbase, let shape = shape(inputs: tx.inputs.count, outputValues: tx.outputs.map(\.valueBtc)) {
            categories.append(shape)
        }
        var dataNames: [String] = []
        for item in embedded where item.isTokenOrInscription && !dataNames.contains(item.name) { dataNames.append(item.name) }
        if !dataNames.isEmpty {
            categories.append(ExplorerTxCategory(name: dataName, detail: "Carries \(dataNames.joined(separator: ", ")). Whether that's spam depends on who you ask."))
        }
        if let height = height, let oldest = tx.inputs.compactMap(\.sourceHeight).min() {
            let age = height - oldest
            if oldest < firstEraEnd, age >= years5Blocks {
                categories.append(ExplorerTxCategory(name: veryOldName, detail: "Spends coins from block \(oldest.withCommas), in Bitcoin's first era (2009 to 2012)."))
            } else if age >= years5Blocks {
                categories.append(ExplorerTxCategory(name: oldName, detail: "Spends coins about \(age / blocksPerYear) years old, from block \(oldest.withCommas)."))
            }
        }
        let spent = Set(tx.inputs.compactMap(\.address))
        if tx.outputs.contains(where: { $0.address.map(spent.contains) ?? false }) {
            categories.append(ExplorerTxCategory(name: backToSenderName, detail: "An output pays an address this transaction also spends from."))
        }
        var noted = Set<String>()
        for address in tx.inputs.compactMap(\.address) + tx.outputs.compactMap(\.address) where noted.insert(address).inserted {
            if let known = ExplorerKnownAddress.note(for: address) {
                categories.append(ExplorerTxCategory(name: known.name, detail: known.detail))
            }
        }
        return categories
    }
}

/// A short list of addresses that are famous, or publicly reported in connection with thefts or
/// seizures. Kept small on purpose, and only with a public record behind each: this isn't a
/// sanctions or risk list, and it says nothing about anyone merely sending to one of these.
enum ExplorerKnownAddress {
    private static let known: [String: (name: String, detail: String)] = [
        "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa": ("Genesis address", "The address of Bitcoin's first block. People still send it coins as a tribute."),
        "1BitcoinEaterAddressDontSendf59kuE": ("Burn address", "A vanity address nobody can have the key to. Coins sent here are gone."),
        "17SkEw2md5avVNyYgj6RiXuQKNwkXaxFyQ": ("Bitcoin Pizza", "Received the 10,000 BTC paid for two pizzas in May 2010."),
        "1FeexV6bAHb8ybZjqQMjJrcCrHGW9sb6uF": ("Mt. Gox theft (1Feex)", "Mt. Gox's former CEO says this address received about 79,956 BTC taken in March 2011. Its owner is unknown."),
        "bc1qazcm763858nkj2dj986etajv6wquslv8uxwczt": ("Bitfinex hack", "Reported as where the 2016 hack's funds were consolidated in 2022, now under US government control."),
        "1HQ3Go3ggs8pFnXuHVHRytPCq5fGG8Hbhx": ("Silk Road funds", "Held about 69,370 BTC taken from Silk Road, seized by the US government in 2020.")
    ]

    static func note(for address: String) -> (name: String, detail: String)? { known[address] }
}

/// Blocks and coins worth a look. Each coin is checked live, against the node's own UTXO set.
enum ExplorerFamous {
    struct Coin: Identifiable {
        let title: String
        let detail: String
        let descriptor: String
        var id: String { title }
    }

    struct Block: Identifiable {
        let height: Int
        let title: String
        let detail: String
        var id: Int { height }
    }

    static let coins: [Coin] = [
        Coin(title: "Satoshi's coins (block 1)",
             detail: "The first block mined after genesis, widely believed to be Satoshi's. Never spent. Anything above 50 BTC is dust people sent later.",
             descriptor: "pk(0496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858ee)"),
        Coin(title: "Genesis address",
             detail: "The first block's address. Its own 50 BTC can never be spent, so this is only tributes people sent.",
             descriptor: "addr(1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa)"),
        Coin(title: "Mt. Gox theft (1Feex)",
             detail: "Mt. Gox's former CEO says about 79,956 BTC taken in March 2011 landed here. Its owner is unknown.",
             descriptor: "addr(1FeexV6bAHb8ybZjqQMjJrcCrHGW9sb6uF)"),
        Coin(title: "Burn address",
             detail: "A vanity address nobody can have the key to. Coins here are gone for good.",
             descriptor: "addr(1BitcoinEaterAddressDontSendf59kuE)"),
        Coin(title: "Bitcoin Pizza recipient",
             detail: "Received the 10,000 BTC paid for two pizzas in 2010.",
             descriptor: "addr(17SkEw2md5avVNyYgj6RiXuQKNwkXaxFyQ)")
    ]

    static let blocks: [Block] = [
        Block(height: 0, title: "Genesis", detail: "Where it all began, January 2009."),
        Block(height: 1, title: "Block 1", detail: "The first block mined after genesis."),
        Block(height: 170, title: "First transaction", detail: "Satoshi sends Hal Finney 10 BTC."),
        Block(height: 57_043, title: "Bitcoin Pizza", detail: "10,000 BTC for two pizzas, May 2010."),
        Block(height: 74_638, title: "Value overflow", detail: "A bug created 184 billion BTC. Fixed within hours by a new chain."),
        Block(height: 210_000, title: "First halving", detail: "The reward drops from 50 to 25 BTC, 2012."),
        Block(height: 420_000, title: "Second halving", detail: "25 to 12.5 BTC, 2016."),
        Block(height: 481_824, title: "SegWit activates", detail: "August 2017."),
        Block(height: 630_000, title: "Third halving", detail: "12.5 to 6.25 BTC, 2020."),
        Block(height: 709_632, title: "Taproot activates", detail: "November 2021."),
        Block(height: 840_000, title: "Fourth halving", detail: "6.25 to 3.125 BTC, 2024.")
    ]
}

/// `scantxoutset`'s reply.
struct ExplorerScanResult {
    struct Coin: Identifiable {
        let txid: String
        let vout: Int
        let amountBtc: Double
        let height: Int
        /// From the descriptor Core reports for it.
        let address: String?
        var id: String { "\(txid):\(vout)" }
    }

    let btc: Double
    let coins: [Coin]

    init?(response: [String: Any]) {
        guard response["success"] as? Bool == true, let total = RPCValue.double(response["total_amount"]) else { return nil }
        btc = total
        coins = ((response["unspents"] as? [[String: Any]]) ?? []).compactMap { row in
            guard let txid = RPCValue.string(row["txid"]), let vout = RPCValue.int(row["vout"]) else { return nil }
            var address: String?
            if let desc = RPCValue.string(row["desc"]), desc.hasPrefix("addr("), let end = desc.firstIndex(of: ")") {
                address = String(desc[desc.index(desc.startIndex, offsetBy: 5)..<end])
            }
            return Coin(txid: txid, vout: vout, amountBtc: RPCValue.double(row["amount"]) ?? 0, height: RPCValue.int(row["height"]) ?? 0, address: address)
        }
    }

    var summary: String {
        coins.isEmpty ? "Empty right now" : "\(ExplorerFormat.btc(btc)) in \(coins.count.withCommas) coin\(coins.count == 1 ? "" : "s")"
    }
}

/// A block holding some of a wallet's coins. nil height: not confirmed yet.
struct ExplorerCoinBlock: Identifiable {
    struct Coin: Identifiable {
        let txid: String
        let vout: Int
        let amountBtc: Double
        let confirmations: Int
        let label: String?
        var id: String { "\(txid):\(vout)" }
    }

    let height: Int?
    let coins: [Coin]
    var id: Int { height ?? -1 }
    var totalBtc: Double { coins.reduce(0) { $0 + $1.amountBtc } }

    /// `listunspent`'s rows by block: unconfirmed first, then newest to oldest. Its rows give
    /// confirmations, not a height, so `tipHeight` must be the tip they were counted from.
    static func group(utxos: [[String: Any]], tipHeight: Int) -> [ExplorerCoinBlock] {
        var byHeight: [Int?: [Coin]] = [:]
        for utxo in utxos {
            guard let txid = RPCValue.string(utxo["txid"]), let vout = RPCValue.int(utxo["vout"]) else { continue }
            let confirmations = max(RPCValue.int(utxo["confirmations"]) ?? 0, 0)
            let height: Int? = confirmations > 0 ? tipHeight - confirmations + 1 : nil
            let label = RPCValue.string(utxo["label"]).flatMap { $0.isEmpty ? nil : $0 }
            byHeight[height, default: []].append(Coin(txid: txid, vout: vout, amountBtc: RPCValue.double(utxo["amount"]) ?? 0,
                                                      confirmations: confirmations, label: label))
        }
        return byHeight.map { height, coins in
            ExplorerCoinBlock(height: height, coins: coins.sorted { $0.amountBtc > $1.amountBtc })
        }.sorted { ($0.height ?? .max) > ($1.height ?? .max) }
    }
}

/// The current difficulty period and the next halving, from the tip and when the period began.
struct ExplorerChainSchedule {
    static let retargetInterval = 2016
    static let targetSpacing: TimeInterval = 600

    let height: Int
    /// nil on regtest, which never retargets.
    let retarget: Retarget?
    let halvingHeight: Int
    let blocksToHalving: Int
    let subsidyNow: Double
    let subsidyAfter: Double

    struct Retarget {
        let blocksDone: Int
        let blocksLeft: Int
        /// Seconds per block so far this period. nil just after a retarget.
        let averageSpacing: TimeInterval?
        /// Percent the difficulty would change at this pace.
        let projectedChange: Double?
    }

    /// Spacing to use for estimates: this period's pace, or the target until it has one.
    var spacing: TimeInterval { min(max(retarget?.averageSpacing ?? Self.targetSpacing, 300), 1200) }

    init(height: Int, chain: String, tipTime: Int?, periodStartTime: Int?) {
        self.height = height
        let halvingInterval = chain == "regtest" ? 150 : 210_000
        let halvings = height / halvingInterval
        halvingHeight = (halvings + 1) * halvingInterval
        blocksToHalving = halvingHeight - height
        subsidyNow = 50 / pow(2, Double(halvings))
        subsidyAfter = subsidyNow / 2
        guard chain != "regtest" else {
            retarget = nil
            return
        }
        let done = height % Self.retargetInterval
        var spacing: TimeInterval?
        // A few blocks is too few to mean anything.
        if done >= 6, let tip = tipTime, let start = periodStartTime, tip > start {
            spacing = TimeInterval(tip - start) / TimeInterval(done)
        }
        retarget = Retarget(blocksDone: done, blocksLeft: Self.retargetInterval - done, averageSpacing: spacing,
                            // Each period's change is capped at a factor of four either way.
                            projectedChange: spacing.map { (min(max(Self.targetSpacing / $0, 0.25), 4) - 1) * 100 })
    }
}

/// How much a transaction gives away on-chain, with the reasons. Common chain-analysis assumptions,
/// not facts: a good rating doesn't make a transaction private, and says nothing about how it was
/// broadcast.
struct TransactionPrivacyRating: Equatable {
    enum Grade: String {
        case good = "GOOD", fair = "FAIR", poor = "POOR"
    }

    struct Finding: Equatable {
        let isGood: Bool
        let text: String
    }

    let score: Int
    let findings: [Finding]
    /// The output that's probably change, by what gave it away.
    let likelyChange: [Int: String]

    var grade: Grade { score >= 80 ? .good : score >= 50 ? .fair : .poor }

    /// `reused`: output addresses that are known to hold other coins too, from a UTXO scan.
    init(inputs: [(address: String, type: String?)], outputs: [(address: String?, amountBtc: Double, type: String?)], reused: Set<String> = []) {
        var score = 100
        var findings: [Finding] = []
        var change: [Int: String] = [:]
        let spent = Set(inputs.map(\.address).filter { !$0.isEmpty })
        // An OP_RETURN pays nobody.
        let paying = outputs.enumerated().filter { $0.element.address != nil }
        let shape = ExplorerTxCategory.shape(inputs: inputs.count, outputValues: paying.map(\.element.amountBtc))?.name
        let isCoinJoin = shape == "CoinJoin"

        if isCoinJoin {
            findings.append(Finding(isGood: true, text: "Equal outputs make it hard to tell who received what."))
        } else if spent.count > 1 {
            score -= min(10 * (spent.count - 1), 30)
            findings.append(Finding(isGood: false, text: "Spending \(spent.count) addresses together suggests they have one owner."))
        } else if inputs.count == 1 {
            findings.append(Finding(isGood: true, text: "Spends one input, so it links no inputs together."))
        }

        for (index, output) in paying where output.address.map(spent.contains) ?? false {
            change[index] = "Goes back to an address being spent"
        }
        if !change.isEmpty {
            score -= 35
            findings.append(Finding(isGood: false, text: "An output goes back to an address being spent. That shows which one is the change."))
        }
        let reusedOutputs = paying.filter { output in output.element.address.map { reused.contains($0) && !spent.contains($0) } ?? false }
        if !reusedOutputs.isEmpty {
            score -= 25
            findings.append(Finding(isGood: false, text: "\(reusedOutputs.count == 1 ? "An output pays an address" : "\(reusedOutputs.count) outputs pay addresses") holding other coins, which connects these payments."))
        }

        if paying.count == 1 {
            findings.append(Finding(isGood: true, text: "No change output, so nothing to follow to the next spend."))
        } else if paying.count == 2, !isCoinJoin {
            // Which output is change, if it can be told apart.
            let inputTypes = Set(inputs.compactMap(\.type))
            let matching = paying.filter { $0.element.type.map(inputTypes.contains) ?? false }
            if inputTypes.count == 1, matching.count == 1 {
                score -= 15
                findings.append(Finding(isGood: false, text: "Only one output is the same address type as the inputs, so it's probably the change."))
                if change[matching[0].offset] == nil { change[matching[0].offset] = "Same address type as the inputs" }
            }
            let isRound: (Double) -> Bool = { amount in
                let sats = Int((amount * 100_000_000).rounded())
                return sats >= 100_000 && sats % 100_000 == 0
            }
            let round = paying.filter { isRound($0.element.amountBtc) }
            if round.count == 1 {
                score -= 15
                findings.append(Finding(isGood: false, text: "One round amount suggests the payment, and so the other output is the change."))
                if let other = paying.first(where: { $0.offset != round[0].offset }), change[other.offset] == nil {
                    change[other.offset] = "The other output is a round amount"
                }
            }
        }
        if Set(inputs.compactMap(\.type)).count > 1 {
            score -= 10
            findings.append(Finding(isGood: false, text: "Mixes address types in its inputs, which few wallets do, so it stands out."))
        }

        if isCoinJoin { score = max(score, 85) }
        self.score = min(max(score, 0), 100)
        self.findings = findings
        likelyChange = isCoinJoin ? [:] : change
    }
}

/// A transaction's place in the mempool, from `getmempoolentry`.
struct MempoolPosition {
    let ownRate: Double
    /// What miners effectively see, in sat/vB: unconfirmed parents can drag it down, and a child
    /// paying more can lift it up.
    private(set) var effectiveRate: Double
    let unconfirmedParents: Int
    let unconfirmedChildren: Int
    let firstSeen: Int?
    let isReplaceable: Bool?

    init?(entry: [String: Any]) {
        guard let fees = entry["fees"] as? [String: Any],
              let vsize = RPCValue.double(entry["vsize"]), vsize > 0,
              let fee = RPCValue.double(fees["base"]) else { return nil }
        let own = fee * 100_000_000 / vsize
        // Each size and fee below includes this transaction.
        func rate(_ feeKey: String, _ sizeKey: String) -> Double? {
            guard let packageFee = RPCValue.double(fees[feeKey]),
                  let size = RPCValue.double(entry[sizeKey]), size > 0 else { return nil }
            return packageFee * 100_000_000 / size
        }
        ownRate = own
        // A cheaper parent has to be mined first, so it drags this down. A dearer one doesn't lift it.
        let withParents = min(rate("ancestor", "ancestorsize") ?? own, own)
        // A child paying more pulls this in with it, along with any unconfirmed parents. This
        // transaction is in both packages, so it's taken out of one. A cheaper child changes nothing.
        if rate("descendant", "descendantsize") ?? own > own,
           let ancestorFee = RPCValue.double(fees["ancestor"]), let ancestorSize = RPCValue.double(entry["ancestorsize"]),
           let descendantFee = RPCValue.double(fees["descendant"]), let descendantSize = RPCValue.double(entry["descendantsize"]) {
            let whole = (ancestorFee + descendantFee - fee) * 100_000_000 / (ancestorSize + descendantSize - vsize)
            effectiveRate = max(withParents, whole)
        } else {
            effectiveRate = withParents
        }
        unconfirmedParents = max((RPCValue.int(entry["ancestorcount"]) ?? 1) - 1, 0)
        unconfirmedChildren = max((RPCValue.int(entry["descendantcount"]) ?? 1) - 1, 0)
        // Core 32's cluster mempool says exactly what miners see: this transaction's chunk.
        if let chunkFee = RPCValue.double(fees["chunk"]), let chunkWeight = RPCValue.double(entry["chunkweight"]), chunkWeight > 0 {
            effectiveRate = chunkFee * 100_000_000 / (chunkWeight / 4)
        }
        firstSeen = RPCValue.int(entry["time"])
        isReplaceable = RPCValue.bool(entry["bip125-replaceable"])
    }
}

/// Lays out rectangles of the given areas in `size`, most square first (squarified treemap).
/// `areas` must be sorted largest first; the result has the same order.
enum ExplorerTreemap {
    static func layout(areas: [Double], in size: CGSize) -> [CGRect] {
        let total = areas.reduce(0, +)
        guard total > 0, size.width > 0, size.height > 0 else { return areas.map { _ in .zero } }
        let scale = Double(size.width * size.height) / total
        var result: [CGRect] = []
        result.reserveCapacity(areas.count)
        var remaining = CGRect(origin: .zero, size: size)
        var start = 0

        func worst(_ sum: Double, _ smallest: Double, _ largest: Double, _ side: Double) -> Double {
            let s2 = sum * sum, w2 = side * side
            return max(w2 * largest / s2, s2 / (w2 * smallest))
        }

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start
            var sum = 0.0
            let largest = areas[start] * scale
            var smallest = largest
            var currentWorst = Double.infinity
            while end < areas.count {
                let area = areas[end] * scale
                let nextSum = sum + area
                let nextSmallest = min(smallest, area)
                let nextWorst = worst(nextSum, nextSmallest, largest, side)
                if end > start && nextWorst > currentWorst { break }
                sum = nextSum
                smallest = nextSmallest
                currentWorst = nextWorst
                end += 1
            }
            // Lay the row along the shorter side.
            let thickness = CGFloat(sum / max(side, 0.0001))
            var offset: CGFloat = 0
            let horizontal = remaining.width >= remaining.height
            for index in start..<end {
                let length = CGFloat(areas[index] * scale / max(Double(thickness), 0.0001))
                if horizontal {
                    result.append(CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length))
                } else {
                    result.append(CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness))
                }
                offset += length
            }
            if horizontal {
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY, width: max(remaining.width - thickness, 0), height: remaining.height)
            } else {
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness, width: remaining.width, height: max(remaining.height - thickness, 0))
            }
            start = end
        }
        return result
    }
}
