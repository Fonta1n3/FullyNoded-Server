//
//  SilentPaymentsScanner.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/8/26.
//
//  OVERVIEW
//  --------
//  A long-running background service that follows the local Bitcoin Core node
//  block by block, finds BIP352 Silent Payment outputs belonging to
//  (b_scan, B_spend), and imports each one into a wallet as a watch-only
//  `rawtr(<xonly>)` descriptor via importdescriptors.
//
//  For each tx the receiver computes:
//    A          = sum of the eligible input public keys
//    input_hash = hash_BIP0352/Inputs(smallest_outpoint || A)
//    ecdh       = (input_hash * b_scan) * A
//    t_k        = hash_BIP0352/SharedSecret(ecdh || ser32(k))     k = 0,1,2...
//    P_k        = B_spend + t_k*G              (unlabeled)
//    P_k,m      = B_spend + label_m*G + t_k*G  (labeled, m = 0 is change)
//  Any taproot output whose x-only key equals P_k / P_k,m is ours.
//  The private key for a found output is b_spend + t_k (+ label_m).
//
//  HOW THE SERVICE RUNS
//  --------------------
//  * All state lives on one private serial queue, so there are no data races.
//  * Progress (next height, recent block hashes, pending rescan) is saved to
//    UserDefaults after every block, so the service resumes where it left off
//    after the app restarts.
//  * A block only counts as scanned once it was fetched AND any matches were
//    imported. Any failure (node down, busy, 503, wallet not loaded) is retried
//    with exponential backoff instead of skipping the block.
//  * Reorgs: each block's previousblockhash is checked against the hash saved for
//    the height below; on mismatch the scanner steps back and rescans.
//  * Found outputs are imported with timestamp "now" (cheap), and the lowest
//    found height is remembered. Once the scanner has caught up to the tip, ONE
//    rescanblockchain from that height makes the wallet pick up the historical
//    outputs and any later spends of them. This avoids a full rescan-to-tip for
//    every single payment found while catching up from an old birthday.
//  * When caught up, it polls getblockcount every `pollInterval` seconds.
//
//  Requires Bitcoin Core >= 25 (getblock verbosity 3) and an unpruned node, or
//  at least unpruned from the birthday height onward (verbosity 3 needs undo data).
//

// Foundation: Data, URLSession, JSONSerialization, UserDefaults, DispatchQueue.
import Foundation
// CryptoKit: SHA256 for BIP340-style tagged hashes.
import CryptoKit
// P256K (swift-secp256k1): secp256k1 point add / tweak / multiply.
import P256K


// MARK: - Errors

// Every failure the scanner can hit. Transient ones are retried with backoff.
enum SPError: Error, CustomStringConvertible {
    // Missing/invalid app configuration (no RPC creds, bad URL…).
    case config(String)
    // Network-level failure (node down, timeout, connection refused).
    case transport(String)
    // Non-JSON HTTP response (401 bad creds, 403 whitelist, 503 queue full…).
    case http(Int)
    // bitcoind returned a JSON-RPC error object.
    case rpc(code: Int, message: String)
    // The response parsed but didn't have the shape we expected.
    case badResponse(String)
    // b_scan / B_spend could not be parsed.
    case invalidKey(String)

    // Human-readable text for logs and the onError callback.
    var description: String {
        switch self {
        case .config(let m): return "Config error: \(m)"
        case .transport(let m): return "Network error: \(m)"
        case .http(let code):
            switch code {
            // Wrong rpcuser/rpcpassword.
            case 401: return "HTTP 401: RPC credentials are incorrect. If you changed them in bitcoin.conf, restart the node."
            // rpcwhitelist blocks one of the methods we use.
            case 403: return "HTTP 403: an RPC method is not in your bitcoin.conf rpcwhitelist (needs getblockcount, getblockhash, getblock, getdescriptorinfo, importdescriptors, rescanblockchain, loadwallet)."
            // Core's RPC work queue is full. Transient, retried.
            case 503: return "HTTP 503: node RPC work queue is full, will retry."
            default: return "HTTP \(code) from node."
            }
        case .rpc(let code, let message): return "RPC error \(code): \(message)"
        case .badResponse(let m): return "Unexpected response: \(m)"
        case .invalidKey(let m): return "Invalid key: \(m)"
        }
    }
}

// Bitcoin Core RPC error codes we react to.
enum SPRPCCode {
    // "Requested wallet does not exist or is not loaded".
    static let walletNotFound = -18
    // "Wallet … is already loaded".
    static let walletAlreadyLoaded = -35
}


// MARK: - RPC (optionally wallet-scoped) with Result-based errors

// A scanner-specific RPC call. It differs from BitcoinRPC.command in ways that
// matter for a service that runs forever:
//  * returns Result<Any, SPError>, so failures can't be mistaken for results
//    (the base command reports HTTP 503 as success with result "");
//  * sends credentials in an Authorization header, so special characters in the
//    password can't break the URL;
//  * percent-encodes the wallet name correctly;
//  * takes a per-call timeout (rescanblockchain can run for a long time);
//  * doesn't print the response, since verbosity-3 blocks are several MB each.
extension BitcoinRPC {
    func spCommand(
        // RPC method name, e.g. "getblock".
        method: String,
        // Named params (Core accepts a JSON object as params).
        params: [String: Any],
        // Wallet to target (/wallet/<name>), or nil for node-level RPCs.
        wallet: String? = nil,
        // Seconds without any response data before URLSession gives up.
        timeout: TimeInterval = 120,
        // Called once, on a URLSession background queue.
        completion: @escaping (Result<Any, SPError>) -> Void
    ) {
        // RPC port from settings, default mainnet 8332.
        let port = UserDefaults.standard.string(forKey: "port") ?? "8332"
        // RPC username from settings.
        let user = UserDefaults.standard.string(forKey: "rpcuser") ?? "FullyNoded-Server"

        // Load the stored (encrypted) RPC credentials from Core Data.
        DataManager.retrieve(entityName: .rpcCreds) { creds in
            // No creds saved.
            guard let creds = creds else {
                completion(.failure(.config("No BitcoinRPCCreds saved.")))
                return
            }
            // The password is stored as encrypted Data.
            guard let encryptedPass = creds["password"] as? Data else {
                completion(.failure(.config("No rpc password saved.")))
                return
            }
            // Decrypt with the app's keychain-held key.
            guard let decryptedPass = Crypto.decrypt(encryptedPass) else {
                completion(.failure(.config("Unable to decrypt the rpc password.")))
                return
            }
            // Data → String.
            guard let rpcPassword = String(data: decryptedPass, encoding: .utf8) else {
                completion(.failure(.config("Unable to encode rpc password data to utf8 string.")))
                return
            }

            // Build the optional /wallet/<name> path.
            var path = ""
            if let wallet = wallet {
                // Path-safe characters minus "/", so spaces, "?", "#", "%" and "/"
                // in a wallet name all get percent-encoded.
                let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
                guard let encoded = wallet.addingPercentEncoding(withAllowedCharacters: allowed) else {
                    completion(.failure(.config("Unable to encode wallet name \(wallet).")))
                    return
                }
                path = "/wallet/\(encoded)"
            }

            // Always the local node; no credentials in the URL.
            guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
                completion(.failure(.config("Error converting the url.")))
                return
            }

            // JSON-RPC is a POST.
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = "POST"
            // Core ignores the content type; text/plain matches bitcoin-cli.
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            // HTTP Basic auth header: base64("user:password").
            let auth = Data("\(user):\(rpcPassword)".utf8).base64EncodedString()
            request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")

            // JSON-RPC 1.0 envelope with a random id.
            let body: [String: Any] = [
                "jsonrpc": "1.0",
                "id": UUID().uuidString,
                "method": method,
                "params": params
            ]
            // Serialize the request body.
            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                completion(.failure(.config("Unable to serialize params for \(method).")))
                return
            }
            request.httpBody = jsonData

            // Fire the request on the shared URLSession.
            let task = self.session.dataTask(with: request) { data, response, error in
                // Network failure (node down, timeout…).
                if let error = error {
                    completion(.failure(.transport(error.localizedDescription)))
                    return
                }
                // HTTP status (0 if somehow missing).
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                // Core sends RPC errors as JSON too (often with HTTP 404/500), so
                // try JSON first. Only non-JSON bodies (401/403/503) fall to .http.
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                else {
                    completion(.failure(.http(status)))
                    return
                }

                // "error" is JSON null on success, an object on failure.
                if let err = json["error"] as? [String: Any] {
                    let code = (err["code"] as? NSNumber)?.intValue ?? 0
                    let message = err["message"] as? String ?? "Unknown error from bitcoind"
                    completion(.failure(.rpc(code: code, message: message)))
                    return
                }

                // Success. A JSON null result arrives as NSNull.
                completion(.success(json["result"] ?? NSNull()))
            }
            // Start the request.
            task.resume()
        }
    }
}


// MARK: - Models

// Everything you need to know about one found output, including what you need
// to spend it later. Codable so it can be saved.
// Privacy note: tweakHex/labelTweakHex can't spend anything without b_spend, but
// together with the txid they identify outputs as yours. They're saved in
// UserDefaults, which is a plain-text plist on disk.
struct SPFoundOutput: Codable, Equatable {
    // Txid of the paying transaction (RPC display order).
    let txid: String
    // Output index in that tx.
    let vout: Int
    // 5120<xonly>.
    let scriptPubKeyHex: String
    // t_k (hex). Spend key = b_spend + t_k (+ labelTweakHex) mod n.
    let tweakHex: String
    // Output counter k at which it matched.
    let k: UInt32
    // Label m if it matched a labeled address (0 = change), nil if unlabeled.
    let label: UInt32?
    // label_m tweak (hex) to add to the spend key for labeled outputs.
    let labelTweakHex: String?
    // Block it confirmed in.
    let blockHeight: Int
    let blockHash: String
    // Block header time (unix seconds).
    let blockTime: Int

    // Watch-only descriptor (no checksum) for importdescriptors.
    var descriptor: String { "rawtr(\(String(scriptPubKeyHex.dropFirst(4))))" }
    // Unique id for de-duplication.
    var outpoint: String { "\(txid):\(vout)" }
}

// Result of scanning one block.
struct SPBlockScan {
    // This block's hash.
    let hash: String
    // Parent hash, used for reorg detection (nil only for genesis).
    let previousHash: String?
    // Block header time.
    let time: Int
    // Outputs in this block that belong to us.
    let outputs: [SPFoundOutput]
}


// MARK: - Hex / hash helpers

// Hex <-> Data helpers.
enum SPHex {
    // Lowercase hex digits for fast encoding.
    private static let digits = Array("0123456789abcdef".utf8)

    // Hex string → Data, nil on any invalid char or odd length.
    static func decode(_ hex: String) -> Data? {
        // Trim and lowercase FIRST so an "0X" prefix is handled too.
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip a "0x" prefix only (not occurrences in the middle).
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        // Work on raw UTF-8 bytes (much faster than String indexing).
        let chars = Array(s.utf8)
        // Two hex chars per byte.
        guard chars.count % 2 == 0 else { return nil }
        // Output buffer.
        var data = Data(capacity: chars.count / 2)
        // Walk two characters at a time.
        var i = 0
        while i < chars.count {
            // High and low nibble; nil on a non-hex character.
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            data.append(hi << 4 | lo)
            i += 2
        }
        return data
    }

    // One ASCII hex char → 0...15.
    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        // "0"..."9"
        case 0x30...0x39: return c - 0x30
        // "a"..."f"
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    // Data → lowercase hex (table lookup, no String(format:) per byte).
    static func encode(_ data: Data) -> String {
        var out = [UInt8]()
        out.reserveCapacity(data.count * 2)
        for b in data {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    // Reverse byte order (RPC txid display order ↔ internal order).
    static func reverse(_ hex: String) -> String? {
        guard let d = decode(hex) else { return nil }
        return encode(Data(d.reversed()))
    }
}

// Hash and serialization helpers.
enum SPHash {
    // BIP340 tagged hash: SHA256(SHA256(tag) || SHA256(tag) || msg).
    static func tagged(_ tag: String, _ message: Data) -> Data {
        // SHA256(tag).
        let tagHash = Data(SHA256.hash(data: Data(tag.utf8)))
        // Build the preimage: tagHash || tagHash || message.
        var payload = Data()
        payload.append(tagHash)
        payload.append(tagHash)
        payload.append(message)
        // Final SHA256.
        return Data(SHA256.hash(data: payload))
    }

    // ser32: 4-byte BIG-endian (BIP352's ser32 for k and m).
    static func ser32(_ k: UInt32) -> Data {
        var be = k.bigEndian
        return Data(bytes: &be, count: 4)
    }

    // 4-byte LITTLE-endian, used for the vout part of an outpoint.
    static func ser32LE(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }
}


// MARK: - RIPEMD-160 / HASH160

// Minimal RIPEMD-160 (CryptoKit doesn't provide it), needed for HASH160 =
// RIPEMD160(SHA256(x)) when finding the pubkey in P2PKH scriptSigs.
// A direct port of the BIP352 repo's test-only ripemd160.py. The logic was
// checked against the standard RIPEMD-160 test vectors.
enum SPRIPEMD160 {
    // Message word order for the left and right lines.
    private static let ML: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
    ]
    private static let MR: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
    ]
    // Rotation amounts for the left and right lines.
    private static let RL: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
    ]
    private static let RR: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
    ]
    // Round constants.
    private static let KL: [UInt32] = [0, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]
    private static let KR: [UInt32] = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0]

    // The five boolean functions f1…f5 (i = 0…4).
    private static func f(_ x: UInt32, _ y: UInt32, _ z: UInt32, _ i: Int) -> UInt32 {
        switch i {
        case 0: return x ^ y ^ z
        case 1: return (x & y) | (~x & z)
        case 2: return (x | ~y) ^ z
        case 3: return (x & z) | (y & ~z)
        default: return x ^ (y | ~z)
        }
    }

    // 32-bit rotate left (n is always 5…15 here).
    private static func rol(_ x: UInt32, _ n: UInt32) -> UInt32 {
        return (x << n) | (x >> (32 - n))
    }

    // Process one 64-byte block into the state `h`.
    private static func compress(_ h: inout [UInt32], _ block: ArraySlice<UInt8>) {
        // 16 little-endian 32-bit words.
        var x = [UInt32](repeating: 0, count: 16)
        let base = block.startIndex
        for i in 0..<16 {
            let o = base + 4 * i
            let b0 = UInt32(block[o])
            let b1 = UInt32(block[o + 1]) << 8
            let b2 = UInt32(block[o + 2]) << 16
            let b3 = UInt32(block[o + 3]) << 24
            x[i] = b0 | b1 | b2 | b3
        }
        // Left and right line state.
        var al = h[0], bl = h[1], cl = h[2], dl = h[3], el = h[4]
        var ar = h[0], br = h[1], cr = h[2], dr = h[3], er = h[4]
        // 80 rounds, both lines.
        for j in 0..<80 {
            let rnd = j >> 4
            // Left line (&+ = wrapping add).
            var t = al &+ f(bl, cl, dl, rnd) &+ x[ML[j]] &+ KL[rnd]
            t = rol(t, RL[j]) &+ el
            al = el; el = dl; dl = rol(cl, 10); cl = bl; bl = t
            // Right line.
            t = ar &+ f(br, cr, dr, 4 - rnd) &+ x[MR[j]] &+ KR[rnd]
            t = rol(t, RR[j]) &+ er
            ar = er; er = dr; dr = rol(cr, 10); cr = br; br = t
        }
        // Combine into the new state.
        let t = h[1] &+ cl &+ dr
        h[1] = h[2] &+ dl &+ er
        h[2] = h[3] &+ el &+ ar
        h[3] = h[4] &+ al &+ br
        h[4] = h[0] &+ bl &+ cr
        h[0] = t
    }

    // RIPEMD-160 of `data` (20 bytes).
    static func hash(_ data: Data) -> Data {
        let msg = [UInt8](data)
        // Initial state.
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
        // Full 64-byte blocks.
        let full = msg.count / 64
        for b in 0..<full {
            compress(&h, msg[(64 * b) ..< (64 * (b + 1))])
        }
        // Tail + 0x80 + zero padding to 56 mod 64 + 64-bit little-endian bit length.
        var fin = Array(msg[(64 * full)...])
        fin.append(0x80)
        while fin.count % 64 != 56 { fin.append(0) }
        let bitLen = UInt64(msg.count) * 8
        for i in 0..<8 { fin.append(UInt8(truncatingIfNeeded: bitLen >> (8 * UInt64(i)))) }
        for b in 0..<(fin.count / 64) {
            compress(&h, fin[(64 * b) ..< (64 * (b + 1))])
        }
        // Output state words little-endian.
        var out = Data(capacity: 20)
        for v in h {
            for i in 0..<4 { out.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) }
        }
        return out
    }

    // HASH160(x) = RIPEMD160(SHA256(x)).
    static func hash160(_ data: Data) -> Data {
        return hash(Data(SHA256.hash(data: data)))
    }
}


// MARK: - Input pubkey extraction (BIP352)

// Classifies prevout scripts and pulls the public key out of eligible inputs.
enum SPPrevout {
    // BIP341 "NUMS" point H: an x-only key with no known private key. A taproot
    // script-path spend using it as the internal key is excluded by BIP352.
    static let numsH = "50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"

    // Witness version (0...16) if the script is a witness program, else nil.
    // A witness program is exactly: <OP_0 or OP_1..OP_16> <push of 2..40 bytes>,
    // with nothing else. Checking the length stops scripts that merely START with
    // OP_2..OP_16 (e.g. bare 2-of-3 multisig "52 21 …") being mistaken for one.
    static func witnessVersion(_ scriptHex: String) -> Int? {
        guard let s = SPHex.decode(scriptHex), s.count >= 4, s.count <= 42 else { return nil }
        // Use offsets relative to startIndex to be safe with Data slices.
        let op = s[s.startIndex]
        let pushLen = Int(s[s.startIndex + 1])
        // The push must be 2...40 bytes and cover the rest of the script exactly.
        guard pushLen >= 2, pushLen <= 40, s.count == pushLen + 2 else { return nil }
        // OP_0 → v0.
        if op == 0x00 { return 0 }
        // OP_1 (0x51) … OP_16 (0x60) → v1 … v16.
        if op >= 0x51 && op <= 0x60 { return Int(op) - 0x50 }
        return nil
    }

    // True if the prevout is segwit v2..v16. BIP352: skip the whole tx if any input
    // spends one.
    static func isSegwitV2Plus(_ scriptHex: String) -> Bool {
        guard let v = witnessVersion(scriptHex) else { return false }
        return v >= 2
    }

    // P2TR = OP_1 PUSH32 <32 bytes>: 34 bytes / 68 hex chars starting "5120".
    static func isP2TR(_ scriptHex: String) -> Bool {
        let s = scriptHex.lowercased()
        return s.count == 68 && s.hasPrefix("5120")
    }

    // P2WPKH = OP_0 PUSH20 <20 bytes>: 22 bytes / 44 hex chars starting "0014".
    static func isP2WPKH(_ scriptHex: String) -> Bool {
        let s = scriptHex.lowercased()
        return s.count == 44 && s.hasPrefix("0014")
    }

    // P2PKH = DUP HASH160 PUSH20 <20> EQUALVERIFY CHECKSIG: 25 bytes / 50 hex.
    static func isP2PKH(_ scriptHex: String) -> Bool {
        let s = scriptHex.lowercased()
        return s.count == 50 && s.hasPrefix("76a914") && s.hasSuffix("88ac")
    }

    // P2SH = HASH160 PUSH20 <20> EQUAL: 23 bytes / 46 hex.
    static func isP2SH(_ scriptHex: String) -> Bool {
        let s = scriptHex.lowercased()
        return s.count == 46 && s.hasPrefix("a914") && s.hasSuffix("87")
    }

    /// Compressed 33-byte pubkey hex if this input is eligible for shared-secret derivation.
    /// The caller has already checked that `vin` has a prevout.
    static func extractEligiblePubkey(vin: [String: Any]) -> String? {
        // Needs getblock verbosity 3, which includes vin.prevout.
        guard let prev = vin["prevout"] as? [String: Any],
              let spkObj = prev["scriptPubKey"] as? [String: Any],
              let spk = (spkObj["hex"] as? String)?.lowercased()
        else { return nil }

        // v2+ inputs are never eligible (scanTx already skipped the tx).
        if isSegwitV2Plus(spk) { return nil }

        // Witness stack items as hex strings (empty for legacy inputs).
        let txinwitness = (vin["txinwitness"] as? [String] ?? []).map { $0.lowercased() }
        // scriptSig hex (empty for native segwit).
        let scriptSig = ((vin["scriptSig"] as? [String: Any])?["hex"] as? String ?? "").lowercased()

        // P2TR: use the output key lifted to even Y ("02" + xonly), UNLESS it's a
        // script-path spend whose internal key is the NUMS point H.
        if isP2TR(spk) {
            var stack = txinwitness
            // BIP341 annex: with ≥ 2 witness items, a last item starting with 0x50
            // is the annex. Remove it before looking at the rest.
            if stack.count >= 2, let last = stack.last, last.hasPrefix("50") {
                stack.removeLast()
            }
            // Script path = still ≥ 2 items. The last one is the control block:
            // 1 byte (leaf version | parity) + 32-byte internal key + merkle path.
            if stack.count >= 2, let control = stack.last, control.count >= 66 {
                let internalKey = String(control.dropFirst(2).prefix(64))
                // The sender excluded this input from A, so we must too.
                if internalKey == numsH { return nil }
            }
            // Key path (or a normal script path): even-Y output key.
            return "02" + String(spk.dropFirst(4))
        }

        // P2WPKH: witness [sig, pubkey]. Uncompressed keys are ignored (per spec).
        if isP2WPKH(spk) {
            if txinwitness.count == 2, let pk = txinwitness.last, isCompressedPub(pk) { return pk }
            return nil
        }

        // P2SH-P2WPKH: scriptSig is EXACTLY one push of the 22-byte redeem script
        // (0x16 0014<20 bytes> = 23 bytes = 46 hex), witness [sig, pubkey].
        // Any other P2SH (multisig, P2SH-P2WSH…) is ineligible. (Like the BIP352
        // reference code, this doesn't re-check HASH160(redeem); consensus already
        // guarantees it for a confirmed spend.)
        if isP2SH(spk) {
            if scriptSig.count == 46, scriptSig.hasPrefix("160014"),
               txinwitness.count == 2, let pk = txinwitness.last, isCompressedPub(pk) {
                return pk
            }
            return nil
        }

        // P2PKH: normally scriptSig = <sig> <pubkey>, but a third party can malleate
        // the scriptSig. Per spec, find the 33-byte compressed key whose HASH160 matches
        // the scriptPubKey hash (uncompressed keys → ineligible).
        if isP2PKH(spk) {
            return pubkeyFromP2PKHScriptSig(scriptSig, scriptPubKeyHex: spk)
        }

        // Anything else (P2WSH, bare scripts, P2A anchors…) contributes no key.
        return nil
    }

    // 33-byte SEC1 compressed key: 66 hex chars starting 02/03.
    private static func isCompressedPub(_ hex: String) -> Bool {
        return hex.count == 66 && (hex.hasPrefix("02") || hex.hasPrefix("03"))
    }

    // BIP352 P2PKH rule: slide a 33-byte window from the END of the scriptSig
    // toward the start and return the first window that starts with 02/03 and whose
    // HASH160 equals the 20-byte hash in the scriptPubKey. For a standard scriptSig
    // the key is the last push, so the first window matches (one hash). A
    // malleated scriptSig is still handled.
    private static func pubkeyFromP2PKHScriptSig(_ scriptSigHex: String, scriptPubKeyHex: String) -> String? {
        // 76 a9 14 <20-byte hash> 88 ac → hash is bytes 3..<23.
        guard let spk = SPHex.decode(scriptPubKeyHex), spk.count == 25 else { return nil }
        let wantHash = Data(spk[spk.startIndex + 3 ..< spk.startIndex + 23])
        // Work on a zero-based byte array.
        guard let sig = SPHex.decode(scriptSigHex) else { return nil }
        let bytes = [UInt8](sig)
        // `end` is the exclusive end of the window.
        var end = bytes.count
        while end >= 33 {
            let window = bytes[(end - 33) ..< end]
            // Only compressed-key-looking windows are worth hashing.
            if let first = window.first, first == 0x02 || first == 0x03 {
                let candidate = Data(window)
                if SPRIPEMD160.hash160(candidate) == wantHash {
                    return SPHex.encode(candidate)
                }
            }
            end -= 1
        }
        // No compressed key found (e.g. an uncompressed-key spend) → ineligible.
        return nil
    }
}


// MARK: - Parsed scan keys (parsed once, reused for every tx)

// b_scan / B_spend parsed and validated once, with the label table precomputed.
// Parsing these for every tx in every block was a big waste before.
struct SPScanKeys {
    // Upper bound on k per BIP352 (K_max): at most 2323 outputs to one recipient
    // per tx. The k loop stops at the first k with no match, so this cap rarely
    // costs anything.
    static let kMax: UInt32 = 2323

    // One label entry: m, its tweak label_m, and B_m = B_spend + label_m·G.
    struct Label {
        let m: UInt32
        let tweak: Data
        let spend: P256K.Signing.PublicKey
    }

    // Raw 32-byte b_scan (needed for label tweaks).
    let scanPrivData: Data
    // b_scan as a secp256k1 private key.
    let scanPriv: P256K.Signing.PrivateKey
    // B_spend as a point.
    let spendPub: P256K.Signing.PublicKey
    // Labels to scan: always m = 0 (change) plus any extra labels you hand out.
    let labels: [Label]

    init(scanPrivateKeyHex: String, spendPublicKeyHex: String, extraLabels: [UInt32]) throws {
        // b_scan must be 32 bytes.
        guard let scanData = SPHex.decode(scanPrivateKeyHex), scanData.count == 32 else {
            throw SPError.invalidKey("b_scan must be 32-byte hex")
        }
        // B_spend must be 33-byte compressed.
        guard let spendData = SPHex.decode(spendPublicKeyHex), spendData.count == 33 else {
            throw SPError.invalidKey("B_spend must be 33-byte compressed hex")
        }
        // Parse into curve objects (throws if out of range / not on the curve).
        // Built in locals first, then assigned to self at the end.
        let priv: P256K.Signing.PrivateKey
        let spend: P256K.Signing.PublicKey
        do {
            priv = try P256K.Signing.PrivateKey(dataRepresentation: scanData)
            spend = try P256K.Signing.PublicKey(dataRepresentation: spendData, format: .compressed)
        } catch {
            throw SPError.invalidKey("b_scan or B_spend is not a valid secp256k1 key: \(error)")
        }

        // m = 0 is reserved for change and MUST always be scanned. Deduplicate and sort.
        let ms = Array(Set([0] + extraLabels)).sorted()
        var built: [Label] = []
        for m in ms {
            // label_m = hash_BIP0352/Label(ser256(b_scan) || ser32(m)).
            let tweak = SilentPaymentCrypto.labelTweak(bScan: scanData, m: m)
            do {
                // B_m = B_spend + label_m·G.
                built.append(Label(m: m, tweak: tweak, spend: try spend.add(Array(tweak))))
            } catch {
                throw SPError.invalidKey("Could not derive label \(m): \(error)")
            }
        }

        scanPrivData = scanData
        scanPriv = priv
        spendPub = spend
        labels = built
    }
}


// MARK: - BIP352 math

// The elliptic-curve side of BIP352.
enum SilentPaymentCrypto {
    // One matched output.
    struct Match {
        // Output index in the tx.
        let vout: Int
        // x-only key of the output.
        let xonly: String
        // t_k.
        let tweak: Data
        // k at which it matched.
        let k: UInt32
        // Label entry if labeled, nil if unlabeled.
        let label: SPScanKeys.Label?
    }

    // A = Σ input pubkeys, returned compressed. Throws if the sum is the point
    // at infinity (the spec says to skip such a tx).
    static func sumCompressedPubkeys(_ hexKeys: [String]) throws -> Data {
        // Parse each hex key into a secp256k1 public key.
        let pubs = try hexKeys.map { hex -> P256K.Signing.PublicKey in
            guard let data = SPHex.decode(hex) else {
                throw SPError.badResponse("bad input pubkey \(hex)")
            }
            return try P256K.Signing.PublicKey(dataRepresentation: data, format: .compressed)
        }
        // Nothing to sum.
        guard let first = pubs.first else { throw SPError.badResponse("no input pubkeys") }
        // One key: the sum is itself.
        if pubs.count == 1 { return Data(first.dataRepresentation) }
        // Point-add the rest onto the first (secp256k1_ec_pubkey_combine).
        let sum = try first.combine(Array(pubs.dropFirst()), format: .compressed)
        return Data(sum.dataRepresentation)
    }

    // input_hash = hash_BIP0352/Inputs(outpoint_L || A).
    static func inputHash(smallestOutpoint: Data, aSumCompressed: Data) -> Data {
        SPHash.tagged("BIP0352/Inputs", smallestOutpoint + aSumCompressed)
    }

    /// outpoint as serialized in a tx: txid (internal LE byte order) || vout uint32 LE
    static func outpointBytes(txidBE: String, vout: UInt32) -> Data? {
        // RPC shows txids byte-reversed, so reverse back to internal order.
        guard let rev = SPHex.reverse(txidBE), let txidLE = SPHex.decode(rev), txidLE.count == 32 else { return nil }
        // 32-byte txid + 4-byte LE vout = 36 bytes.
        return txidLE + SPHash.ser32LE(vout)
    }

    // label_m = hash_BIP0352/Label(ser256(b_scan) || ser32(m)).
    static func labelTweak(bScan: Data, m: UInt32) -> Data {
        SPHash.tagged("BIP0352/Label", bScan + SPHash.ser32(m))
    }

    // Scan one tx. Returns every matching output with its t_k, k and label.
    static func scanTransaction(
        // Pre-parsed b_scan / B_spend / labels.
        keys: SPScanKeys,
        // Eligible input pubkeys (compressed hex).
        inputPubkeysCompressed: [String],
        // ALL input outpoints (eligible or not), used to find the smallest one.
        inputs: [(txid: String, vout: UInt32)],
        // Every taproot output in the tx: (vout index, x-only key).
        taprootOutputs: [(vout: Int, xonly: String)]
    ) throws -> [Match] {
        // No eligible inputs or no taproot outputs → nothing can match.
        guard !inputPubkeysCompressed.isEmpty, !taprootOutputs.isEmpty else { return [] }

        // A = Σ eligible input pubkeys.
        let aSum = try sumCompressedPubkeys(inputPubkeysCompressed)

        // Lexicographically smallest 36-byte serialized outpoint.
        guard let smallest = inputs
            .compactMap({ outpointBytes(txidBE: $0.txid, vout: $0.vout) })
            .min(by: { $0.lexicographicallyPrecedes($1) })
        else { return [] }

        // input_hash.
        let ih = inputHash(smallestOutpoint: smallest, aSumCompressed: aSum)

        // input_hash · b_scan (mod n), a scalar tweak-multiply.
        let tweakedScan = try keys.scanPriv.multiply(Array(ih))
        // A as a point.
        let aSumPub = try P256K.Signing.PublicKey(dataRepresentation: aSum, format: .compressed)
        // ecdh_shared_secret = (input_hash · b_scan) · A.
        let sharedPub = try aSumPub.multiply(Array(tweakedScan.dataRepresentation), format: .compressed)
        // serP(ecdh), 33 bytes compressed.
        let sharedPoint = Data(sharedPub.dataRepresentation)

        // Outputs not yet matched, x-only → vout (a matched output can't match again).
        var remaining: [String: Int] = [:]
        for o in taprootOutputs { remaining[o.xonly.lowercased()] = o.vout }

        // Accumulated matches.
        var found: [Match] = []
        // Output counter.
        var k: UInt32 = 0

        // Spec loop: try k = 0, 1, 2… and stop at the first k with no match.
        // k runs 0 ..< K_max (at most 2323 outputs), as in the reference code.
        while k < SPScanKeys.kMax, !remaining.isEmpty {
            // t_k = hash_BIP0352/SharedSecret(serP(ecdh) || ser32(k)).
            let tk = SPHash.tagged("BIP0352/SharedSecret", sharedPoint + SPHash.ser32(k))

            // Did any variant match at this k?
            var hit = false

            // Unlabeled: P_k = B_spend + t_k·G. Compare x-only (parity doesn't
            // matter for P2TR).
            let unlabeledX = SPHex.encode(Data(try keys.spendPub.add(Array(tk)).xonly.bytes))
            if let vout = remaining.removeValue(forKey: unlabeledX) {
                found.append(Match(vout: vout, xonly: unlabeledX, tweak: tk, k: k, label: nil))
                hit = true
            }

            // Labeled: P_k,m = B_m + t_k·G. Equivalent to the spec's "output − P_k,
            // then look up in the label table", at O(#labels) point ops per k. Fine
            // for a handful of labels; switch to the table method for many.
            for label in keys.labels {
                let labeledX = SPHex.encode(Data(try label.spend.add(Array(tk)).xonly.bytes))
                if let vout = remaining.removeValue(forKey: labeledX) {
                    found.append(Match(vout: vout, xonly: labeledX, tweak: tk, k: k, label: label))
                    hit = true
                }
            }

            // Nothing matched at this k → no higher k can match.
            if !hit { break }
            k += 1
        }

        return found
    }
}


// MARK: - Block scanner (stateless: fetch one block, return its matches)

enum SilentPaymentScanner {
    // Fetch block `height` with prevouts and scan every tx in it.
    // Fails (instead of returning []) on ANY RPC or data problem, so the caller
    // can retry the same height rather than silently skipping a block.
    static func scanBlock(
        height: Int,
        keys: SPScanKeys,
        completion: @escaping (Result<SPBlockScan, SPError>) -> Void
    ) {
        // Height → block hash.
        BitcoinRPC.shared.spCommand(method: "getblockhash", params: ["height": height]) { result in
            let hash: String
            switch result {
            case .failure(let e):
                completion(.failure(e))
                return
            case .success(let value):
                // Must be a real 64-char hash.
                guard let h = value as? String, h.count == 64 else {
                    completion(.failure(.badResponse("getblockhash(\(height)) returned \(value)")))
                    return
                }
                hash = h
            }

            // verbosity 3 includes vin.prevout.scriptPubKey (Core ≥ 25). Large
            // blocks can take a while to serialize, hence the longer timeout.
            BitcoinRPC.shared.spCommand(
                method: "getblock",
                params: ["blockhash": hash, "verbosity": 3],
                timeout: 300
            ) { result in
                switch result {
                case .failure(let e):
                    completion(.failure(e))
                case .success(let value):
                    // Pull the fields we need.
                    guard let block = value as? [String: Any],
                          let txs = block["tx"] as? [[String: Any]],
                          let time = (block["time"] as? NSNumber)?.intValue
                    else {
                        completion(.failure(.badResponse("getblock \(hash) had no tx/time")))
                        return
                    }
                    let prevHash = block["previousblockhash"] as? String

                    // Scan every tx. scanTx throws only when the block data is unusable
                    // (e.g. no prevouts), which fails the whole block.
                    do {
                        var found: [SPFoundOutput] = []
                        for tx in txs {
                            found += try scanTx(tx, keys: keys, blockHeight: height, blockHash: hash, blockTime: time)
                        }
                        completion(.success(SPBlockScan(hash: hash, previousHash: prevHash, time: time, outputs: found)))
                    } catch let e as SPError {
                        completion(.failure(e))
                    } catch {
                        completion(.failure(.badResponse("\(error)")))
                    }
                }
            }
        }
    }

    // Pull inputs and outputs from one decoded tx and run the BIP352 check.
    private static func scanTx(
        _ tx: [String: Any],
        keys: SPScanKeys,
        blockHeight: Int,
        blockHash: String,
        blockTime: Int
    ) throws -> [SPFoundOutput] {
        // Need txid, vin and vout.
        guard let txid = tx["txid"] as? String,
              let vins = tx["vin"] as? [[String: Any]],
              let vouts = tx["vout"] as? [[String: Any]]
        else { throw SPError.badResponse("tx without txid/vin/vout in block \(blockHash)") }

        // Coinbase: no real inputs, so it can't be a silent payment.
        if vins.first?["coinbase"] != nil { return [] }

        // Every non-coinbase input must have a prevout. If it doesn't, the node
        // can't provide undo data (pruned block, or Core < 25). Scanning without
        // prevouts would silently find nothing, so fail loudly instead.
        if vins.contains(where: { $0["prevout"] == nil }) {
            throw SPError.badResponse("block \(blockHeight) has no prevout data. The node is pruned below this height or Core is older than v25.")
        }

        // BIP352: skip the whole tx if any input spends segwit v2+.
        if vins.contains(where: { vin in
            guard let prev = vin["prevout"] as? [String: Any],
                  let spk = (prev["scriptPubKey"] as? [String: Any])?["hex"] as? String
            else { return false }
            return SPPrevout.isSegwitV2Plus(spk)
        }) {
            return []
        }

        // (vout index, x-only key) of every P2TR output. Uses vout["n"], falling
        // back to the array position (they're always equal in Core's output).
        let tapOutputs: [(vout: Int, xonly: String)] = vouts.enumerated().compactMap { idx, vout in
            guard let hex = (vout["scriptPubKey"] as? [String: Any])?["hex"] as? String,
                  SPPrevout.isP2TR(hex)
            else { return nil }
            let n = (vout["n"] as? NSNumber)?.intValue ?? idx
            return (vout: n, xonly: String(hex.lowercased().dropFirst(4)))
        }
        // No taproot outputs → can't be a silent payment.
        guard !tapOutputs.isEmpty else { return [] }

        // Eligible pubkeys and ALL outpoints.
        var pubkeys: [String] = []
        var outpoints: [(txid: String, vout: UInt32)] = []
        for vin in vins {
            // Every input's outpoint goes into the smallest-outpoint calculation.
            if let prevTxid = vin["txid"] as? String, let n = (vin["vout"] as? NSNumber)?.uint32Value {
                outpoints.append((txid: prevTxid, vout: n))
            }
            // Only eligible inputs contribute a pubkey to A.
            if let pk = SPPrevout.extractEligiblePubkey(vin: vin) {
                pubkeys.append(pk)
            }
        }
        // No eligible inputs → no shared secret.
        guard !pubkeys.isEmpty else { return [] }

        // Run the math. A crypto failure here is specific to this tx (e.g. input keys
        // that sum to infinity, which the spec says to skip), so it doesn't fail the block.
        let matches: [SilentPaymentCrypto.Match]
        do {
            matches = try SilentPaymentCrypto.scanTransaction(
                keys: keys,
                inputPubkeysCompressed: pubkeys,
                inputs: outpoints,
                taprootOutputs: tapOutputs
            )
        } catch {
            #if DEBUG
            print("SP: skipping tx \(txid): \(error)")
            #endif
            return []
        }

        // Keep everything needed to import and later spend.
        return matches.map { m in
            SPFoundOutput(
                txid: txid,
                vout: m.vout,
                scriptPubKeyHex: "5120" + m.xonly,
                tweakHex: SPHex.encode(m.tweak),
                k: m.k,
                label: m.label?.m,
                labelTweakHex: m.label.map { SPHex.encode($0.tweak) },
                blockHeight: blockHeight,
                blockHash: blockHash,
                blockTime: blockTime
            )
        }
    }
}


// MARK: - Persisted scan state

// Everything the service needs to resume after a restart.
struct SPScanState: Codable {
    // Next height to scan. Everything below it is scanned AND imported.
    var nextHeight: Int
    // height → hash of recently scanned blocks, for reorg detection.
    var recentHashes: [Int: String] = [:]
    // Lowest height with a found output that the wallet hasn't rescanned yet.
    var pendingRescanFrom: Int?
    // Every output found so far.
    var found: [SPFoundOutput] = []

    // How many recent block hashes to keep (reorgs deeper than this aren't handled).
    static let reorgDepth = 200
}


// MARK: - Long-running scanner → importer service

final class SilentPaymentService {
    // Singleton.
    static let shared = SilentPaymentService()

    // Seconds between getblockcount polls once caught up to the tip.
    var pollInterval: TimeInterval = 15
    // Set these callbacks BEFORE calling start(); they're read on the service queue.
    // Called on the main queue with outputs as soon as they're imported.
    var onFound: (([SPFoundOutput]) -> Void)?
    // Called on the main queue with every error (the service keeps retrying).
    var onError: ((SPError) -> Void)?
    // Called on the main queue after each block with (scanned height, tip).
    var onProgress: ((Int, Int) -> Void)?

    // ALL mutable state below is only touched on this serial queue.
    private let queue = DispatchQueue(label: "FullyNoded-Server.SilentPaymentService", qos: .utility)

    // Loop on/off flag.
    private var running = false
    // Bumped on every start/stop so stale timers and callbacks from a previous
    // run exit instead of running a second loop in parallel.
    private var generation = 0
    // Current config.
    private var walletName = ""
    private var scanPublicKeyHex = ""
    private var keys: SPScanKeys?
    // Persisted state and the UserDefaults key it lives under.
    private var state = SPScanState(nextHeight: 0)
    private var stateKey = ""
    // Current retry delay (exponential backoff, reset on success).
    private var retryDelay: TimeInterval = 5
    private let maxRetryDelay: TimeInterval = 300

    // Enforce singleton.
    private init() {}

    /// Start following the chain. Validates the keys up front (throws on bad keys).
    /// If a saved state exists for this wallet + key pair it resumes from it;
    /// otherwise it starts at `birthdayHeight` (the first block that could pay you).
    func start(
        walletName: String,
        scanPrivateKeyHex: String,
        scanPublicKeyHex: String,
        spendPublicKeyHex: String,
        birthdayHeight: Int,
        extraLabels: [UInt32] = []
    ) throws {
        // Parse and validate once. A typo now throws here instead of looking like
        // "no payments found" forever.
        let parsed = try SPScanKeys(
            scanPrivateKeyHex: scanPrivateKeyHex,
            spendPublicKeyHex: spendPublicKeyHex,
            extraLabels: extraLabels
        )
        // State key per (wallet, scan pub, spend pub), hashed so no key material
        // appears in the defaults key.
        let id = SPHex.encode(Data(SHA256.hash(data: Data("\(walletName)|\(scanPublicKeyHex.lowercased())|\(spendPublicKeyHex.lowercased())".utf8)))).prefix(16)
        let key = "sp_state_\(id)"

        queue.async {
            // Stop any previous run first.
            self.generation += 1
            self.running = true
            self.walletName = walletName
            self.scanPublicKeyHex = scanPublicKeyHex.lowercased()
            self.keys = parsed
            self.stateKey = key
            self.retryDelay = 5
            // Resume saved progress, or start at the birthday.
            self.state = Self.loadState(key: key) ?? SPScanState(nextHeight: max(birthdayHeight, 0))
            self.log("started at height \(self.state.nextHeight)")
            self.step(self.generation)
        }
    }

    // Stop. In-flight RPCs finish, but their callbacks see the new generation and exit.
    func stop() {
        queue.async {
            self.running = false
            self.generation += 1
            self.log("stopped")
        }
    }

    // All outputs found so far (thread-safe snapshot).
    func foundOutputs() -> [SPFoundOutput] {
        queue.sync { state.found }
    }

    // MARK: Loop

    // True if the callback belongs to the current run.
    private func isCurrent(_ gen: Int) -> Bool {
        running && gen == generation
    }

    // Run `step` again after `delay` seconds, on our queue.
    private func schedule(_ gen: Int, after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isCurrent(gen) else { return }
            self.step(gen)
        }
    }

    // A transient failure: report it, wait, and retry the SAME step. Never skips.
    private func retry(_ gen: Int, _ error: SPError) {
        log("error: \(error), retrying in \(Int(retryDelay))s")
        let cb = onError
        DispatchQueue.main.async { cb?(error) }
        schedule(gen, after: retryDelay)
        retryDelay = min(retryDelay * 2, maxRetryDelay)
    }

    // One iteration: get the tip, then either scan the next block or (when caught
    // up) finish any pending rescan and wait for the next block.
    private func step(_ gen: Int) {
        guard isCurrent(gen) else { return }

        BitcoinRPC.shared.spCommand(method: "getblockcount", params: [:]) { [weak self] result in
            guard let self = self else { return }
            // Hop back onto our queue before touching state.
            self.queue.async {
                guard self.isCurrent(gen) else { return }
                switch result {
                case .failure(let e):
                    // Node down / warming up / busy → retry later.
                    self.retry(gen, e)
                case .success(let value):
                    guard let tip = (value as? NSNumber)?.intValue else {
                        self.retry(gen, .badResponse("getblockcount returned \(value)"))
                        return
                    }
                    if self.state.nextHeight <= tip {
                        // Behind the tip: scan the next block.
                        self.processBlock(self.state.nextHeight, tip: tip, gen: gen)
                    } else if let from = self.state.pendingRescanFrom {
                        // Caught up with imports waiting for a rescan: do it now.
                        self.rescan(from: from, gen: gen)
                    } else {
                        // Caught up, nothing pending: wait for the next block.
                        // (A reorg that shortens the chain is caught when the next
                        // block arrives and its parent hash doesn't match.)
                        self.schedule(gen, after: self.pollInterval)
                    }
                }
            }
        }
    }

    // Scan one height, handle reorgs, import matches, then advance.
    private func processBlock(_ height: Int, tip: Int, gen: Int) {
        guard let keys = keys else { return }

        SilentPaymentScanner.scanBlock(height: height, keys: keys) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.isCurrent(gen) else { return }
                switch result {
                case .failure(let e):
                    // Don't advance: this exact height is retried.
                    self.retry(gen, e)

                case .success(let block):
                    // Reorg check: this block's parent must be the block we scanned
                    // at height - 1. If not, that block was reorged out: forget it
                    // and step back one height. Repeats until the chains agree again.
                    if let expected = self.state.recentHashes[height - 1],
                       let parent = block.previousHash, parent != expected {
                        self.log("reorg detected at height \(height - 1), stepping back")
                        self.state.recentHashes[height - 1] = nil
                        // Drop outputs we recorded from the orphaned block. Their
                        // descriptors stay imported, which is harmless (watch-only).
                        self.state.found.removeAll { $0.blockHash == expected }
                        self.state.nextHeight = height - 1
                        self.saveState()
                        self.queue.async { self.step(gen) }
                        return
                    }

                    // Nothing found: mark scanned and move on.
                    guard !block.outputs.isEmpty else {
                        self.finishBlock(height, block: block, tip: tip, gen: gen)
                        return
                    }

                    // Found outputs: import them, and only advance once that worked.
                    self.log("found \(block.outputs.count) output(s) at height \(height): \(block.outputs.map { $0.outpoint })")
                    self.importOutputs(block.outputs) { importResult in
                        self.queue.async {
                            guard self.isCurrent(gen) else { return }
                            switch importResult {
                            case .failure(let e):
                                // Height isn't advanced, so the block is rescanned and
                                // the import retried (re-importing is idempotent).
                                self.retry(gen, e)
                            case .success:
                                // Record outputs (de-duplicated by outpoint).
                                let known = Set(self.state.found.map { $0.outpoint })
                                self.state.found += block.outputs.filter { !known.contains($0.outpoint) }
                                // Remember the lowest height the wallet must rescan from.
                                self.state.pendingRescanFrom = min(self.state.pendingRescanFrom ?? height, height)
                                let cb = self.onFound
                                let outs = block.outputs
                                DispatchQueue.main.async { cb?(outs) }
                                self.finishBlock(height, block: block, tip: tip, gen: gen)
                            }
                        }
                    }
                }
            }
        }
    }

    // Mark `height` as fully done, save progress, and continue immediately.
    private func finishBlock(_ height: Int, block: SPBlockScan, tip: Int, gen: Int) {
        // Remember this block's hash for reorg checks, and trim old entries.
        state.recentHashes[height] = block.hash
        state.recentHashes = state.recentHashes.filter { $0.key > height - SPScanState.reorgDepth }
        // Advance and save after EVERY block, so a restart loses nothing.
        state.nextHeight = height + 1
        saveState()
        // Success resets the backoff.
        retryDelay = 5
        let cb = onProgress
        DispatchQueue.main.async { cb?(height, tip) }
        // Next iteration. Async so the call stack doesn't grow.
        queue.async { self.step(gen) }
    }

    // MARK: Import

    // Import outputs as watch-only rawtr() descriptors, in ONE importdescriptors call.
    // Uses timestamp "now" (no rescan). The historical rescan happens once in
    // rescan(from:) after the scanner has caught up.
    private func importOutputs(_ outputs: [SPFoundOutput], completion: @escaping (Result<Void, SPError>) -> Void) {
        // Copy what we need now (we're on `queue`); the callbacks below run on
        // URLSession's queue and must not read service state.
        let wallet = walletName
        let scanPub = scanPublicKeyHex
        // Add checksums one at a time via getdescriptorinfo (a node-level RPC).
        var remaining = outputs
        var requests: [[String: Any]] = []

        func sendImport() {
            Self.walletCall(wallet: wallet, method: "importdescriptors", params: ["requests": requests], timeout: 600) { result in
                switch result {
                case .failure(let e):
                    completion(.failure(e))
                case .success(let value):
                    // [{success: Bool, error?: {message}}] per request.
                    guard let arr = value as? [[String: Any]], arr.count == requests.count else {
                        completion(.failure(.badResponse("importdescriptors returned \(value)")))
                        return
                    }
                    if let failed = arr.first(where: { ($0["success"] as? Bool) != true }) {
                        let msg = (failed["error"] as? [String: Any])?["message"] as? String ?? "importdescriptors failed"
                        completion(.failure(.rpc(code: 0, message: msg)))
                        return
                    }
                    completion(.success(()))
                }
            }
        }

        func nextChecksum() {
            guard let out = remaining.first else {
                sendImport()
                return
            }
            remaining.removeFirst()
            BitcoinRPC.shared.spCommand(method: "getdescriptorinfo", params: ["descriptor": out.descriptor]) { result in
                switch result {
                case .failure(let e):
                    completion(.failure(e))
                case .success(let value):
                    guard let desc = (value as? [String: Any])?["descriptor"] as? String else {
                        completion(.failure(.badResponse("getdescriptorinfo returned no descriptor")))
                        return
                    }
                    // Label shows up in listunspent / listtransactions. The scan PUBKEY
                    // is public (it's part of the SP address), so it's safe to include.
                    var label = "sp scan=\(scanPub) k=\(out.k)"
                    if let m = out.label { label += " m=\(m)" }
                    requests.append([
                        "desc": desc,
                        "timestamp": "now",
                        "internal": false,
                        "active": false,
                        "label": label
                    ])
                    nextChecksum()
                }
            }
        }

        nextChecksum()
    }

    // Once caught up: rescan the wallet from the lowest found height, so it sees the
    // historical outputs (and any later spends of them).
    private func rescan(from height: Int, gen: Int) {
        log("rescanning wallet \(walletName) from height \(height)")
        // Core sends nothing until the rescan finishes, so allow a long idle time.
        // If it still times out, Core keeps rescanning. The retry then gets "Wallet is
        // currently rescanning" (backoff) until it finishes, and a quick second rescan
        // completes the job.
        Self.walletCall(wallet: walletName, method: "rescanblockchain", params: ["start_height": height], timeout: 6 * 3600) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.isCurrent(gen) else { return }
                switch result {
                case .failure(let e):
                    self.retry(gen, e)
                case .success:
                    // Only clear it if nothing lower was added meanwhile.
                    if let pending = self.state.pendingRescanFrom, pending >= height {
                        self.state.pendingRescanFrom = nil
                    }
                    self.saveState()
                    self.retryDelay = 5
                    self.log("rescan complete")
                    self.queue.async { self.step(gen) }
                }
            }
        }
    }

    // Wallet RPC that loads the wallet and retries once if it isn't loaded
    // (after a node restart, wallets without load_on_startup are unloaded).
    // Static and takes the wallet name as a parameter, so it never reads service
    // state from a URLSession callback queue.
    private static func walletCall(wallet: String, method: String, params: [String: Any], timeout: TimeInterval, completion: @escaping (Result<Any, SPError>) -> Void) {
        BitcoinRPC.shared.spCommand(method: method, params: params, wallet: wallet, timeout: timeout) { result in
            // Anything other than "wallet not loaded" goes straight back.
            guard case .failure(.rpc(let code, _)) = result, code == SPRPCCode.walletNotFound else {
                completion(result)
                return
            }
            // Not loaded → loadwallet, then try the original call once more.
            BitcoinRPC.shared.spCommand(method: "loadwallet", params: ["filename": wallet], timeout: 600) { loadResult in
                if case .failure(let e) = loadResult {
                    // "Already loaded" (e.g. loaded by someone else meanwhile) is fine;
                    // anything else (wallet doesn't exist…) is a real error.
                    var alreadyLoaded = false
                    if case .rpc(let c, _) = e, c == SPRPCCode.walletAlreadyLoaded { alreadyLoaded = true }
                    if !alreadyLoaded {
                        completion(.failure(e))
                        return
                    }
                }
                BitcoinRPC.shared.spCommand(method: method, params: params, wallet: wallet, timeout: timeout, completion: completion)
            }
        }
    }

    // MARK: Persistence

    // Load saved state for a key, nil if none or unreadable.
    private static func loadState(key: String) -> SPScanState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SPScanState.self, from: data)
    }

    // Save current state (called after every block).
    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }

    // Debug logging.
    private func log(_ message: String) {
        #if DEBUG
        print("SP: \(message)")
        #endif
    }
}

 /*
  Usage (e.g. at app launch, after the node is running):

  The wallet must be a WATCH-ONLY descriptor wallet, because Core refuses to import
  rawtr(<xonly>) (no private key) into a wallet with private keys enabled:
    bitcoin-cli -named createwallet wallet_name=sp-watch disable_private_keys=true load_on_startup=true

  // Set callbacks first (they're read on the service queue).
  SilentPaymentService.shared.onFound = { outputs in print("received", outputs) }
  SilentPaymentService.shared.onError = { error in print(error) }

  do {
      try SilentPaymentService.shared.start(
          walletName: "sp-watch",
          scanPrivateKeyHex: "e1…32-byte-hex…",
          scanPublicKeyHex: "03…",
          spendPublicKeyHex: "02…",
          birthdayHeight: 840_000,                 // only used the first time
          extraLabels: []                          // add m ≥ 1 if you hand out labeled addresses
      )
  } catch {
      print("SP keys invalid: \(error)")
  }
 */
