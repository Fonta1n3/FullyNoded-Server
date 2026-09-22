//
//  SilentPaymentsScanner.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/8/26.
//

import Foundation


// MARK: - Wallet-scoped RPC (same behavior as BitcoinRPC.command, + /wallet/<name>)

extension BitcoinRPC {
    func command(
        method: String,
        params: [String: Any],
        wallet: String,
        completion: @escaping ((result: Any?, error: String?)) -> Void
    ) {
        let port = UserDefaults.standard.string(forKey: "port") ?? "8332"
        let nodeIp = "127.0.0.1:\(port)"
        let user = UserDefaults.standard.string(forKey: "rpcuser") ?? "FullyNoded-Server"

        DataManager.retrieve(entityName: .rpcCreds) { [weak self] creds in
            guard let self = self else { return }

            guard let creds = creds else {
                completion((nil, "No BitcoinRPCCreds saved."))
                return
            }
            guard let encryptedPass = creds["password"] as? Data else {
                completion((nil, "No rpc password saved."))
                return
            }
            guard let decryptedPass = Crypto.decrypt(encryptedPass) else {
                completion((nil, "Unable to decrypt the rpc password."))
                return
            }
            guard let rpcPassword = String(data: decryptedPass, encoding: .utf8) else {
                completion((nil, "Unable to encode rpc password data to utf8 string."))
                return
            }

            let encodedWallet = wallet.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(charactersIn: "/").inverted
            ) ?? wallet

            let stringUrl = "http://\(user):\(rpcPassword)@\(nodeIp)/wallet/\(encodedWallet)"
            guard let url = URL(string: stringUrl) else {
                completion((nil, "Error converting the url."))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

            let dict: [String: Any] = [
                "jsonrpc": "1.0",
                "id": UUID().uuidString,
                "method": method,
                "params": params
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
                completion((nil, "converting to jsonData failing..."))
                return
            }

            request.httpBody = jsonData

            let task = session.dataTask(with: request) { data, response, error in
                guard let urlContent = data else {
                    completion((nil, error?.localizedDescription))
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: urlContent, options: .mutableLeaves) as? NSDictionary else {
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 401:
                            completion((nil, "Looks like your rpc credentials are incorrect, please double check them. If you changed your rpc creds in your bitcoin.conf you need to restart your node for the changes to take effect."))
                        case 503:
                            completion(("", nil))
                        case 403:
                            completion((nil, "Http error 403, this usually means you are trying to use an rpc command (\(method)) which is not included in your bitcoin.conf rpcwhitelist. See Bitcoin Core debug.log for details."))
                        default:
                            completion((nil, "Unable to decode the response from your node, http status code: \(httpResponse.statusCode)"))
                        }
                    } else {
                        completion((nil, "Unable to decode the response from your node..."))
                    }
                    return
                }

                #if DEBUG
                print("json: \(json)")
                #endif

                guard let errorCheck = json["error"] as? NSDictionary else {
                    completion((json["result"], nil))
                    return
                }

                guard let errorMessage = errorCheck["message"] as? String else {
                    completion((nil, "Uknown error from bitcoind"))
                    return
                }

                completion((nil, errorMessage))
            }
            task.resume()
        }
    }
}

// MARK: - One-shot import

enum SilentPaymentImport {
    static func importScriptPubKey(
        walletName: String,
        scanPublicKey: String,
        spendPublicKey: String? = nil,
        scriptPubKeyHex: String,
        timestamp: UInt64? = nil,
        label: String? = nil,
        completion: @escaping ((result: Any?, error: String?)) -> Void
    ) {
        let spk = norm(scriptPubKeyHex)

        guard spk.count == 68, spk.hasPrefix("5120") else {
            completion((nil, "Not a silent-payment P2TR scriptPubKey: \(scriptPubKeyHex)"))
            return
        }

        let xonly = String(spk.dropFirst(4))

        BitcoinRPC.shared.command(
            method: "getdescriptorinfo",
            params: ["descriptor": "rawtr(\(xonly))"],
            wallet: walletName
        ) { result, error in
            if let error = error {
                completion((nil, error))
                return
            }

            guard
                let info = result as? [String: Any],
                let descriptor = info["descriptor"] as? String
            else {
                completion((nil, "getdescriptorinfo returned no descriptor."))
                return
            }

            var item: [String: Any] = [
                "desc": descriptor,
                "timestamp": timestamp.map { $0 as Any } ?? "now",
                "internal": false,
                "active": false
            ]

            var tag = "sp scan=\(norm(scanPublicKey))"
            if let spend = spendPublicKey {
                tag += " spend=\(norm(spend))"
            }
            if let label = label, !label.isEmpty {
                tag += " \(label)"
            }
            item["label"] = tag

            BitcoinRPC.shared.command(
                method: "importdescriptors",
                params: ["requests": [item]],
                wallet: walletName
            ) { importResult, importError in
                if let importError = importError {
                    completion((nil, importError))
                    return
                }

                if let arr = importResult as? [[String: Any]],
                   let first = arr.first,
                   let success = first["success"] as? Bool,
                   !success {
                    let msg = (first["error"] as? [String: Any])?["message"] as? String
                        ?? "importdescriptors failed"
                    completion((importResult, msg))
                    return
                }

                completion((importResult, nil))
            }
        }
    }

    static func importScriptPubKeys(
        walletName: String,
        scanPublicKey: String,
        spendPublicKey: String? = nil,
        scriptPubKeys: [String],
        timestamp: UInt64? = nil,
        completion: @escaping ((result: Any?, error: String?)) -> Void
    ) {
        var remaining = scriptPubKeys
        var collected: [Any] = []

        func next() {
            guard let spk = remaining.first else {
                completion((collected, nil))
                return
            }
            remaining.removeFirst()

            importScriptPubKey(
                walletName: walletName,
                scanPublicKey: scanPublicKey,
                spendPublicKey: spendPublicKey,
                scriptPubKeyHex: spk,
                timestamp: timestamp
            ) { result, error in
                if let error = error {
                    completion((collected, error))
                    return
                }
                if let result = result {
                    collected.append(result)
                }
                next()
            }
        }

        next()
    }

    static func norm(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "0x", with: "")
    }
}

// MARK: - Start it

enum SilentPaymentImportRunner {
    static func importOutputs(
        walletName: String,
        scanPublicKey: String,
        spendPublicKey: String?,
        scriptPubKeys: [String],
        completion: @escaping ((result: Any?, error: String?)) -> Void
    ) {
        let fresh = scriptPubKeys
            .map { SilentPaymentImport.norm($0) }
            .filter { $0.count == 68 && $0.hasPrefix("5120") }

        guard !fresh.isEmpty else {
            completion(([], nil))
            return
        }

        SilentPaymentImport.importScriptPubKeys(
            walletName: walletName,
            scanPublicKey: scanPublicKey,
            spendPublicKey: spendPublicKey,
            scriptPubKeys: fresh,
            timestamp: nil, // importScriptPubKey already uses "now" when nil
            completion: completion
        )
    }
}

/*
 SilentPaymentImportRunner.start(
     walletName: "your_wallet_name",
     scanPublicKey: "03…",
     spendPublicKey: "02…"
 ) { scanPub, spendPub, done in
     YourScanner.shared.findScriptPubKeys(scanPub: scanPub, spendPub: spendPub) { outputs in
         done(outputs)
     }
 }
*/


 
 //import Foundation
 import CryptoKit
 import P256K

 // MARK: - Models

 struct SPFoundOutput {
     let txid: String
     let vout: Int
     let scriptPubKeyHex: String
     let tweakHex: String
     let k: UInt32
     let blockHeight: Int
 }

 // MARK: - Hex / hash helpers

 enum SPHex {
     static func decode(_ hex: String) -> Data? {
         let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
             .replacingOccurrences(of: "0x", with: "")
             .lowercased()
         guard s.count % 2 == 0 else { return nil }
         var data = Data()
         data.reserveCapacity(s.count / 2)
         var idx = s.startIndex
         while idx < s.endIndex {
             let next = s.index(idx, offsetBy: 2)
             guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
             data.append(b)
             idx = next
         }
         return data
     }

     static func encode(_ data: Data) -> String {
         data.map { String(format: "%02x", $0) }.joined()
     }

     static func reverse(_ hex: String) -> String? {
         guard let d = decode(hex) else { return nil }
         return encode(Data(d.reversed()))
     }
 }

 enum SPHash {
     static func tagged(_ tag: String, _ message: Data) -> Data {
         let tagData = Data(tag.utf8)
         let tagHash = Data(SHA256.hash(data: tagData))
         var payload = Data()
         payload.append(tagHash)
         payload.append(tagHash)
         payload.append(message)
         return Data(SHA256.hash(data: payload))
     }

     static func ser32(_ k: UInt32) -> Data {
         var be = k.bigEndian
         return Data(bytes: &be, count: 4)
     }

     static func ser32LE(_ v: UInt32) -> Data {
         var le = v.littleEndian
         return Data(bytes: &le, count: 4)
     }
 }

 // MARK: - Input pubkey extraction (BIP352)

 enum SPPrevout {
     static func isSegwitV2Plus(_ scriptHex: String) -> Bool {
         let s = scriptHex.lowercased()
         // OP_n (2...16) + push: 0x52..0x60 followed by pushlen, or OP_SUCCESS / future
         guard s.count >= 4 else { return false }
         guard let op = UInt8(s.prefix(2), radix: 16) else { return false }
         // witness v0 = 0x00, v1 = 0x51. Anything 0x52–0x60 with a push is v2+
         return op >= 0x52 && op <= 0x60
     }

     static func isP2TR(_ scriptHex: String) -> Bool {
         let s = scriptHex.lowercased()
         return s.count == 68 && s.hasPrefix("5120")
     }

     static func isP2WPKH(_ scriptHex: String) -> Bool {
         let s = scriptHex.lowercased()
         return s.count == 44 && s.hasPrefix("0014")
     }

     static func isP2PKH(_ scriptHex: String) -> Bool {
         let s = scriptHex.lowercased()
         return s.count == 50 && s.hasPrefix("76a914") && s.hasSuffix("88ac")
     }

     static func isP2SH(_ scriptHex: String) -> Bool {
         let s = scriptHex.lowercased()
         return s.count == 46 && s.hasPrefix("a914") && s.hasSuffix("87")
     }

     /// Compressed 33-byte pubkey hex if this input is eligible for shared-secret derivation.
     static func extractEligiblePubkey(vin: [String: Any]) -> String? {
         guard let prev = vin["prevout"] as? [String: Any],
               let spkObj = prev["scriptPubKey"] as? [String: Any],
               let spk = (spkObj["hex"] as? String)?.lowercased()
         else { return nil }

         if isSegwitV2Plus(spk) { return nil }

         let txinwitness = vin["txinwitness"] as? [String] ?? []
         let scriptSig = (vin["scriptSig"] as? [String: Any])?["hex"] as? String ?? ""

         // P2TR: always use the output key, even-Y compressed
         if isP2TR(spk) {
             let xonly = String(spk.dropFirst(4))
             return "02" + xonly
         }

         // P2WPKH: witness [sig, pubkey]
         if isP2WPKH(spk), let pk = txinwitness.last, isCompressedPub(pk) {
             return pk.lowercased()
         }

         // P2SH-P2WPKH: scriptSig pushes 0014{20}, witness [sig, pubkey]
         if isP2SH(spk) {
             let redeem = redeemScriptFromScriptSig(scriptSig)
             if let redeem, isP2WPKH(redeem), let pk = txinwitness.last, isCompressedPub(pk) {
                 return pk.lowercased()
             }
             return nil
         }

         // P2PKH: scriptSig <sig> <pubkey>
         if isP2PKH(spk), let pk = pubkeyFromP2PKHScriptSig(scriptSig), isCompressedPub(pk) {
             return pk.lowercased()
         }

         return nil
     }

     private static func isCompressedPub(_ hex: String) -> Bool {
         let h = hex.lowercased()
         return h.count == 66 && (h.hasPrefix("02") || h.hasPrefix("03"))
     }

     private static func redeemScriptFromScriptSig(_ scriptSigHex: String) -> String? {
         guard let data = SPHex.decode(scriptSigHex), data.count >= 23 else { return nil }
         // typical: push 22 (0x16) + 0014{20}
         if data[0] == 0x16, data.count >= 23 {
             return SPHex.encode(data.dropFirst(1).prefix(22))
         }
         return nil
     }

     private static func pubkeyFromP2PKHScriptSig(_ scriptSigHex: String) -> String? {
         guard let data = SPHex.decode(scriptSigHex), data.count >= 34 else { return nil }
         let lenIndex = data.count - 34
         guard data[lenIndex] == 33 else { return nil }
         return SPHex.encode(data.suffix(33))
     }
 }

 // MARK: - BIP352 math

 enum SilentPaymentCrypto {
     static func sumCompressedPubkeys(_ hexKeys: [String]) throws -> Data {
         let pubs = try hexKeys.map {
             guard let data = SPHex.decode($0) else {
                 throw NSError(domain: "SP", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad input pubkey"])
             }
             return try P256K.Signing.PublicKey(dataRepresentation: data, format: .compressed)
         }

         if pubs.count == 1 {
             return Data(pubs[0].dataRepresentation)
         }
         
         let sum = try pubs[0].combine(Array(pubs.dropFirst()), format: .compressed)
         return Data(sum.dataRepresentation)
     }

     static func inputHash(smallestOutpoint: Data, aSumCompressed: Data) -> Data {
         var msg = Data()
         msg.append(smallestOutpoint)
         msg.append(aSumCompressed)
         return SPHash.tagged("BIP0352/Inputs", msg)
     }

     /// outpoint as serialized in a tx: txid (internal LE byte order) || vout uint32 LE
     static func outpointBytes(txidBE: String, vout: UInt32) -> Data? {
         guard let rev = SPHex.reverse(txidBE), let txidLE = SPHex.decode(rev) else { return nil }
         return txidLE + SPHash.ser32LE(vout)
     }

     static func labelTweak(bScan: Data, m: UInt32) -> Data {
         SPHash.tagged("BIP0352/Label", bScan + SPHash.ser32(m))
     }

     static func scanTransaction(
         bScanHex: String,
         bSpendCompressedHex: String,
         inputPubkeysCompressed: [String],
         inputs: [(txid: String, vout: UInt32)],
         taprootOutputXonly: [String],
         extraLabels: [UInt32] = [],
         maxK: UInt32 = 10
     ) throws -> [(xonly: String, tweak: String, k: UInt32, label: UInt32?)] {
         guard !inputPubkeysCompressed.isEmpty, !taprootOutputXonly.isEmpty else { return [] }

         let pubs = try inputPubkeysCompressed.map {
             guard let data = SPHex.decode($0) else {
                 throw NSError(domain: "SP", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad input pubkey"])
             }
             return try P256K.Signing.PublicKey(dataRepresentation: data, format: .compressed)
         }
         let aSum: Data
         if pubs.count == 1 {
             aSum = Data(pubs[0].dataRepresentation)
         } else {
             aSum = Data(try pubs[0].combine(Array(pubs.dropFirst()), format: .compressed).dataRepresentation)
         }

         guard let smallest = inputs
             .compactMap({ outpointBytes(txidBE: $0.txid, vout: $0.vout) })
             .min(by: { $0.lexicographicallyPrecedes($1) })
         else { return [] }

         let ih = inputHash(smallestOutpoint: smallest, aSumCompressed: aSum)

         guard let scanPrivData = SPHex.decode(bScanHex), scanPrivData.count == 32 else {
             throw NSError(domain: "SP", code: 2, userInfo: [NSLocalizedDescriptionKey: "b_scan must be 32-byte hex"])
         }
         guard let spendData = SPHex.decode(bSpendCompressedHex), spendData.count == 33 else {
             throw NSError(domain: "SP", code: 3, userInfo: [NSLocalizedDescriptionKey: "B_spend must be 33-byte compressed hex"])
         }

         let scanPriv = try P256K.Signing.PrivateKey(dataRepresentation: scanPrivData)
         let tweakedScan = try scanPriv.multiply(Array(ih))
         let aSumPub = try P256K.Signing.PublicKey(dataRepresentation: aSum, format: .compressed)
         let sharedPub = try aSumPub.multiply(Array(tweakedScan.dataRepresentation), format: .compressed)
         let sharedPoint = Data(sharedPub.dataRepresentation)

         let spendPub = try P256K.Signing.PublicKey(dataRepresentation: spendData, format: .compressed)

         // m = 0 is reserved for change and MUST always be scanned.
         let labelsToScan: [UInt32] = Array(Set([0] + extraLabels)).sorted()
         var labeledSpend: [(UInt32, P256K.Signing.PublicKey)] = []
         for m in labelsToScan {
             let lt = labelTweak(bScan: scanPrivData, m: m)
             labeledSpend.append((m, try spendPub.add(Array(lt))))
         }

         var remaining = Set(taprootOutputXonly.map { $0.lowercased() })
         var found: [(String, String, UInt32, UInt32?)] = []
         var k: UInt32 = 0

         while k <= maxK, !remaining.isEmpty {
             let tk = SPHash.tagged("BIP0352/SharedSecret", sharedPoint + SPHash.ser32(k))

             let unlabeled = try spendPub.add(Array(tk))
             let unlabeledX = SPHex.encode(Data(unlabeled.xonly.bytes))

             var hit = false

             if remaining.contains(unlabeledX) {
                 found.append((unlabeledX, SPHex.encode(tk), k, nil))
                 remaining.remove(unlabeledX)
                 hit = true
             }

             for (m, bm) in labeledSpend {
                 let labeled = try bm.add(Array(tk))
                 let labeledX = SPHex.encode(Data(labeled.xonly.bytes))
                 if remaining.contains(labeledX) {
                     found.append((labeledX, SPHex.encode(tk), k, m))
                     remaining.remove(labeledX)
                     hit = true
                 }
             }

             if !hit { break }
             k += 1
         }

         return found.map { (xonly: $0.0, tweak: $0.1, k: $0.2, label: $0.3) }
     }
 }

 // MARK: - Core block scanner

 final class SilentPaymentScanner {
     static let shared = SilentPaymentScanner()

     private let heightKey = "sp_scan_height"
     var startHeight: Int {
         get { UserDefaults.standard.object(forKey: heightKey) as? Int ?? 0 }
         set { UserDefaults.standard.set(newValue, forKey: heightKey) }
     }

     private init() {}

     /// Scan new blocks and return P2TR scriptPubKeys that belong to (b_scan, B_spend).
     func fetchOutputs(
         scanPrivateKeyHex: String,
         spendPublicKeyHex: String,
         completion: @escaping ([String]) -> Void
     ) {
         BitcoinRPC.shared.command(method: "getblockcount", params: [:]) { [weak self] result, error in
             guard let self = self else { return }
             if error != nil {
                 completion([])
                 return
             }
             let tip = (result as? Int) ?? (result as? NSNumber)?.intValue ?? 0
             var height = self.startHeight
             if UserDefaults.standard.object(forKey: heightKey) == nil {
                 height = tip // or a wallet birthday you pass in
             }
             if height <= 0 { height = max(tip - 1, 0) }

             var collected: [String] = []

             func nextBlock() {
                 if height > tip {
                     self.startHeight = tip
                     completion(collected)
                     return
                 }
                 self.scanBlock(
                     height: height,
                     scanPrivateKeyHex: scanPrivateKeyHex,
                     spendPublicKeyHex: spendPublicKeyHex
                 ) { spks in
                     collected.append(contentsOf: spks)
                     height += 1
                     nextBlock()
                 }
             }
             nextBlock()
         }
     }

     func scanBlock(
         height: Int,
         scanPrivateKeyHex: String,
         spendPublicKeyHex: String,
         completion: @escaping ([String]) -> Void
     ) {
         BitcoinRPC.shared.command(
             method: "getblockhash",
             params: ["height": height]
         ) { result, error in
             guard let hash = result as? String, error == nil else {
                 completion([])
                 return
             }

             // verbosity 3 includes vin.prevout.scriptPubKey
             BitcoinRPC.shared.command(
                 method: "getblock",
                 params: ["blockhash": hash, "verbosity": 3]
             ) { block, error in
                 guard let block = block as? [String: Any],
                       let txs = block["tx"] as? [[String: Any]],
                       error == nil
                 else {
                     completion([])
                     return
                 }

                 var found: [String] = []
                 for tx in txs {
                     found.append(contentsOf: Self.scanTx(
                         tx,
                         height: height,
                         scanPrivateKeyHex: scanPrivateKeyHex,
                         spendPublicKeyHex: spendPublicKeyHex
                     ))
                 }
                 completion(found)
             }
         }
     }

     private static func scanTx(
         _ tx: [String: Any],
         height: Int,
         scanPrivateKeyHex: String,
         spendPublicKeyHex: String
     ) -> [String] {
         guard let vins = tx["vin"] as? [[String: Any]],
               let vouts = tx["vout"] as? [[String: Any]]
         else { return [] }

         if vins.contains(where: { vin in
             guard let prev = vin["prevout"] as? [String: Any],
                   let spk = (prev["scriptPubKey"] as? [String: Any])?["hex"] as? String
             else { return false }
             return SPPrevout.isSegwitV2Plus(spk)
         }) {
             return []
         }

         let tapOutputs: [(Int, String)] = vouts.enumerated().compactMap { idx, vout in
             guard let hex = (vout["scriptPubKey"] as? [String: Any])?["hex"] as? String,
                   SPPrevout.isP2TR(hex)
             else { return nil }
             return (idx, hex.lowercased())
         }
         guard !tapOutputs.isEmpty else { return [] }

         var pubkeys: [String] = []
         var outpoints: [(String, UInt32)] = []
         for vin in vins {
             if let txid = vin["txid"] as? String, let vout = vin["vout"] as? Int {
                 outpoints.append((txid, UInt32(vout)))
             }
             if let pk = SPPrevout.extractEligiblePubkey(vin: vin) {
                 pubkeys.append(pk)
             }
         }
         guard !pubkeys.isEmpty else { return [] }

         let xonlys = tapOutputs.map { String($0.1.dropFirst(4)) }

         do {
             let matches = try SilentPaymentCrypto.scanTransaction(
                 bScanHex: scanPrivateKeyHex,
                 bSpendCompressedHex: spendPublicKeyHex,
                 inputPubkeysCompressed: pubkeys,
                 inputs: outpoints,
                 taprootOutputXonly: xonlys
             )
             return matches.map { "5120\($0.xonly)" }
         } catch {
             #if DEBUG
             print("SP scan tx error: \(error)")
             #endif
             return []
         }
     }
 }

 // MARK: - Wire scanner → importer loop

final class SilentPaymentService {
    static let shared = SilentPaymentService()

    private var running = false
    private var nextHeight = 0

    private init() {}

    func start(
        walletName: String,
        scanPrivateKeyHex: String,
        scanPublicKeyHex: String,
        spendPublicKeyHex: String,
        startHeight: Int
    ) {
        guard !running else { return }
        running = true
        nextHeight = startHeight
        loop(
            walletName: walletName,
            scanPrivateKeyHex: scanPrivateKeyHex,
            scanPublicKeyHex: scanPublicKeyHex,
            spendPublicKeyHex: spendPublicKeyHex
        )
    }

    func stop() {
        running = false
    }

    private func loop(
        walletName: String,
        scanPrivateKeyHex: String,
        scanPublicKeyHex: String,
        spendPublicKeyHex: String
    ) {
        guard running else { return }

        BitcoinRPC.shared.command(method: "getblockcount", params: [:]) { [weak self] result, _ in
            guard let self = self, self.running else { return }

            let tip = (result as? NSNumber)?.intValue ?? (result as? Int) ?? -1
            guard tip >= self.nextHeight else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.loop(
                        walletName: walletName,
                        scanPrivateKeyHex: scanPrivateKeyHex,
                        scanPublicKeyHex: scanPublicKeyHex,
                        spendPublicKeyHex: spendPublicKeyHex
                    )
                }
                return
            }

            let height = self.nextHeight
            SilentPaymentScanner.shared.scanBlock(
                height: height,
                scanPrivateKeyHex: scanPrivateKeyHex,
                spendPublicKeyHex: spendPublicKeyHex
            ) { scriptPubKeys in
                let finishBlock = {
                    self.nextHeight = height + 1
                    self.loop(
                        walletName: walletName,
                        scanPrivateKeyHex: scanPrivateKeyHex,
                        scanPublicKeyHex: scanPublicKeyHex,
                        spendPublicKeyHex: spendPublicKeyHex
                    )
                }

                guard !scriptPubKeys.isEmpty else {
                    finishBlock()
                    return
                }

                SilentPaymentImportRunner.importOutputs(
                    walletName: walletName,
                    scanPublicKey: scanPublicKeyHex,
                    spendPublicKey: spendPublicKeyHex,
                    scriptPubKeys: scriptPubKeys
                ) { _, _ in
                    finishBlock()
                }
            }
        }
    }
}

 /*
  SilentPaymentService.start(
      walletName: "sp-watch",
      scanPrivateKeyHex: "e1…32-byte-hex…",
      scanPublicKeyHex: "03…",
      spendPublicKeyHex: "02…",
      fromHeight: 840_000
  )
 */
 
