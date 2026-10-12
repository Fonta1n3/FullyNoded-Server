//
//  SilentPaymentHistoryView.swift
//  FullyNoded-Server
//
//  • SPImportFeed / SPImportedCard: the success alert shown when the scanner imports a
//    silent payment it found.
//  • SPHistoryView (window "SPHistory"): every silent payment output imported into the
//    scanner's wallet, with its rawtr() descriptor.
//
//  Nothing here is stored by FN-Server: the history is read from the Core wallet the
//  outputs were imported into (each import is a rawtr(<xonly>) descriptor there), so it
//  also covers imports from before this window existed.
//

import SwiftUI

// MARK: - Import alert

/// One successful import by the scanner.
struct SPImportEvent: Identifiable, Equatable {
    let id = UUID()
    let count: Int
    /// Total of the outputs whose amount was known (BTC).
    let total: Double?
    let txids: [String]
    let wallet: String
    let blockHeight: Int
}

/// The latest import, shown as a success card in the main window until dismissed.
final class SPImportFeed: ObservableObject {
    static let shared = SPImportFeed()

    @Published var latest: SPImportEvent?

    /// Called on the main queue by the scanner's onFound callback.
    func record(_ outputs: [SPFoundOutput], wallet: String) {
        guard !outputs.isEmpty else { return }
        let amounts = outputs.compactMap { $0.amount }
        let event = SPImportEvent(count: outputs.count,
                                  total: amounts.isEmpty ? nil : amounts.reduce(0, +),
                                  txids: Array(Set(outputs.map { $0.txid })).sorted(),
                                  wallet: wallet,
                                  blockHeight: outputs.map { $0.blockHeight }.max() ?? 0)
        // Several blocks found in a row: merge into one card instead of replacing it.
        if let current = latest {
            latest = SPImportEvent(count: current.count + event.count,
                                   total: (current.total ?? 0) + (event.total ?? 0),
                                   txids: Array(Set(current.txids + event.txids)).sorted(),
                                   wallet: event.wallet,
                                   blockHeight: max(current.blockHeight, event.blockHeight))
        } else {
            latest = event
        }
    }
}

/// Success card over the main window: what was imported, and a way to the history.
struct SPImportedCard: View {
    @ObservedObject var feed = SPImportFeed.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let event = feed.latest {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { } // swallow clicks behind the card

                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Cypher.accent)
                    Text("Silent payment received")
                        .font(Cypher.mono(17, weight: .bold))
                    Text(summary(event))
                        .font(Cypher.mono(12))
                        .foregroundStyle(Cypher.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("View history") {
                            feed.latest = nil
                            openWindow(id: "SPHistory")
                        }
                        Button("OK") { feed.latest = nil }
                            .buttonStyle(.cypherProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(Cypher.panel)
                .overlay(Rectangle().stroke(Cypher.accent, lineWidth: 1))
                .shadow(color: Cypher.accent.opacity(0.25), radius: 24)
            }
            .buttonStyle(.cypher)
            .transition(.opacity)
        }
    }

    private func summary(_ event: SPImportEvent) -> String {
        var text = "\(event.count) output\(event.count == 1 ? "" : "s")"
        if let total = event.total, total > 0 {
            text += " (\(String(format: "%.8f", total)) BTC)"
        }
        text += " found and imported into wallet \"\(event.wallet)\" at block \(event.blockHeight)."
        text += "\n\nThe wallet rescans to pick it up; it shows in Fully Noded once that's done."
        return text
    }
}

// MARK: - History

/// One imported silent payment output, as the wallet knows it.
struct SPHistoryItem: Identifiable {
    var id: String { descriptor }
    let descriptor: String
    let address: String
    let importedAt: Date?
    let amount: Double?
    let confirmations: Int?
    let txids: [String]
    let unspent: Bool
}

final class SPHistoryModel: ObservableObject {
    @Published var items: [SPHistoryItem] = []
    @Published var wallet = ""
    @Published var isLoading = false
    @Published var error: String?
    /// The network of the saved keys (set by load()).
    private var chain = "main"

    func load() {
        guard let config = SPConfigStore.load() else {
            wallet = ""
            items = []
            error = "No silent payment keys are set up yet. Import them on the Silent Payments page."
            return
        }
        // The wallet lives on the keys' network, not necessarily the selected one.
        guard let chain = config.resolvedChain else {
            wallet = config.walletName
            items = []
            error = "These keys are for a test network, but which one wasn't saved. Select that network in Bitcoin Core and refresh."
            return
        }
        self.chain = chain
        wallet = config.walletName
        isLoading = true
        error = nil

        let wallet = config.walletName
        call("listdescriptors", [:], wallet) { [weak self] descriptorsResult in
            guard let self = self else { return }
            guard case .success(let value) = descriptorsResult,
                  let list = (value as? [String: Any])?["descriptors"] as? [[String: Any]] else {
                self.fail(descriptorsResult)
                return
            }
            // FN-Server imports every found output as rawtr(<xonly>).
            let imported = list.compactMap { entry -> (desc: String, xonly: String, date: Date?)? in
                guard let desc = entry["desc"] as? String, desc.hasPrefix("rawtr("),
                      let xonly = Self.xonly(of: desc) else { return nil }
                let date = (entry["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return (desc, xonly, date)
            }

            self.call("listreceivedbyaddress", ["minconf": 0, "include_empty": true, "include_watchonly": true], wallet) { receivedResult in
                var received: [String: [String: Any]] = [:]
                if case .success(let value) = receivedResult {
                    for row in value as? [[String: Any]] ?? [] {
                        if let address = row["address"] as? String { received[address] = row }
                    }
                }
                self.call("listunspent", ["minconf": 0], wallet) { unspentResult in
                    var unspent = Set<String>()
                    if case .success(let value) = unspentResult {
                        for row in value as? [[String: Any]] ?? [] {
                            if let address = row["address"] as? String { unspent.insert(address) }
                        }
                    }

                    let hrp = Self.hrp(for: chain)
                    let items = imported.map { entry -> SPHistoryItem in
                        let address = SPBech32m.p2tr(hrp: hrp, xonlyHex: entry.xonly) ?? ""
                        let row = received[address]
                        return SPHistoryItem(descriptor: entry.desc,
                                             address: address,
                                             importedAt: entry.date,
                                             amount: row?["amount"] as? Double,
                                             confirmations: row?["confirmations"] as? Int,
                                             txids: row?["txids"] as? [String] ?? [],
                                             unspent: unspent.contains(address))
                    }
                    .sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }

                    DispatchQueue.main.async {
                        self.items = items
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func call(_ method: String, _ params: [String: Any], _ wallet: String,
                      completion: @escaping (Result<Any, SPError>) -> Void) {
        BitcoinRPC.shared.spCommand(method: method, params: params, wallet: wallet, chain: chain, completion: completion)
    }

    private func fail(_ result: Result<Any, SPError>) {
        DispatchQueue.main.async {
            self.isLoading = false
            if case .failure(let e) = result {
                self.error = "Unable to read wallet \"\(self.wallet)\": \(e.description)"
            } else {
                self.error = "Unexpected response from the node."
            }
        }
    }

    /// "rawtr([fp]xonly)#checksum" or "rawtr(xonly)" → xonly hex.
    static func xonly(of descriptor: String) -> String? {
        // Exactly 64 hex characters, right after "rawtr(" or a key origin "[…]".
        guard let regex = try? NSRegularExpression(pattern: #"^rawtr\((?:\[[^\]]*\])?([0-9a-fA-F]{64})\)"#),
              let match = regex.firstMatch(in: descriptor, range: NSRange(descriptor.startIndex..., in: descriptor)),
              let range = Range(match.range(at: 1), in: descriptor) else { return nil }
        return String(descriptor[range]).lowercased()
    }

    static func hrp(for chain: String) -> String {
        switch chain {
        case "main": return "bc"
        case "regtest": return "bcrt"
        default: return "tb"
        }
    }
}

/// Bech32m P2TR addresses (BIP350), for showing each imported output's address.
enum SPBech32m {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func p2tr(hrp: String, xonlyHex: String) -> String? {
        guard let program = SPHex.decode(xonlyHex), program.count == 32,
              let data = convert(Array(program)) else { return nil }
        let values = [UInt8(1)] + data
        let checksum = createChecksum(hrp: hrp, values: values)
        return hrp + "1" + String((values + checksum).map { charset[Int($0)] })
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ff_ffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= gen[i] }
        }
        return chk
    }

    private static func createChecksum(hrp: String, values: [UInt8]) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        let expanded = bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
        let mod = polymod(expanded + values + [0, 0, 0, 0, 0, 0]) ^ 0x2bc8_30a3
        return (0..<6).map { UInt8((mod >> (5 * (5 - UInt32($0)))) & 31) }
    }

    private static func convert(_ data: [UInt8]) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        for value in data {
            acc = (acc << 8) | Int(value)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(UInt8((acc >> bits) & 31))
            }
        }
        if bits > 0 { out.append(UInt8((acc << (5 - bits)) & 31)) }
        return out
    }
}

struct SPHistoryView: View {
    @StateObject private var model = SPHistoryModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("Silent Payment History")
                    .font(Cypher.mono(18, weight: .bold))
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button {
                    model.load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            Text(model.wallet.isEmpty
                 ? "Silent payment outputs imported by the scanner."
                 : "Outputs imported into wallet \(model.wallet), newest first. Read from the wallet on your node; FN-Server stores none of this.")
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
                .lineLimit(2)
                .truncationMode(.middle)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Cypher.amber)
                    .font(.caption)
            }

            if model.items.isEmpty && !model.isLoading && model.error == nil {
                Text("No silent payments imported yet.")
                    .foregroundStyle(Cypher.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.items) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { model.load() }
        .onReceive(SPImportFeed.shared.$latest) { event in
            // A new import: refresh so it shows up here straight away.
            if event != nil { model.load() }
        }
    }

    private func row(_ item: SPHistoryItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.amount.map { String(format: "%.8f BTC", $0) } ?? "– BTC")
                        .font(Cypher.mono(14, weight: .semibold))
                    Spacer()
                    status(item)
                }
                if !item.address.isEmpty {
                    Text(item.address)
                        .font(Cypher.mono(11))
                        .textSelection(.enabled)
                }
                if let txid = item.txids.first {
                    Text("txid \(txid)")
                        .font(Cypher.mono(10))
                        .foregroundStyle(Cypher.dim)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(alignment: .top) {
                    Text(item.descriptor)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        Pasteboard.write(item.descriptor)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy descriptor")
                }
            }
        } label: {
            Text(item.importedAt.map { "Imported " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Imported")
        }
    }

    private func status(_ item: SPHistoryItem) -> some View {
        let confirmations = item.confirmations ?? 0
        let (text, color): (String, Color)
        if item.amount == nil || item.amount == 0 {
            (text, color) = ("not seen yet (rescan pending)", Cypher.amber)
        } else if !item.unspent {
            (text, color) = ("spent", Cypher.dim)
        } else if confirmations == 0 {
            (text, color) = ("unconfirmed", Cypher.amber)
        } else {
            (text, color) = ("\(confirmations) conf · unspent", Cypher.accent)
        }
        return Text(text)
            .font(Cypher.mono(11, weight: .semibold))
            .foregroundStyle(color)
    }
}
