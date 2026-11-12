//
//  ExplorerTransactionView.swift
//  FullyNoded-Server
//
//  Transaction analysis: one in the chain or the mempool, or one pasted in and never broadcast
//  (a raw transaction or PSBT). Where the money goes, what the transaction looks like and what it
//  gives away, what data it carries, and where each output went next.
//

import SwiftUI

struct ExplorerTransactionView: View {
    enum Source: Hashable {
        case txid(String, blockhash: String?)
        case pasted(String)
    }

    let source: Source
    let highlightedOutput: Int?
    @ObservedObject private var model = ExplorerModel.shared
    @State private var report: TxReport?
    @State private var error: String?
    @State private var deep = DeepCheck.notRun
    @State private var deepTask: Task<Void, Never>?

    enum DeepCheck: Equatable {
        case notRun
        case running(Double)
        case done(reused: [String: Int])
        case failed(String)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let report = report {
                    header(report)
                    if let accept = report.acceptance { acceptanceBox(accept, report) }
                    if let position = report.position { mempoolBox(position, report) }
                    GroupBox("Flow") {
                        ExplorerFlowView(tx: report.tx, onInput: { trace(report.tx.inputs[$0]) })
                            .frame(height: 220)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        detailsBox(report)
                        privacyBox(report)
                    }
                    if !report.embedded.isEmpty { embeddedBox(report) }
                    inputsBox(report)
                    outputsBox(report)
                } else if let error = error {
                    GroupBox("Couldn't read that") {
                        Text(error).font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.6)
                        Text("Reading it from your node…").font(Cypher.mono(12)).foregroundStyle(Cypher.dim)
                    }
                }
            }
            .padding(16)
        }
        .task {
            do {
                report = try await TxReport.load(source, model: model)
                // Traced here from a coin: show that coin.
                if let highlightedOutput = highlightedOutput {
                    DispatchQueue.main.async { proxy.scrollTo(highlightedOutput, anchor: .center) }
                }
            } catch let failure as ExplorerError {
                error = failure.message
            } catch {
                self.error = error.localizedDescription
            }
        }
        .onDisappear { deepTask?.cancel() }
        }
    }

    // MARK: - Header

    private func header(_ report: TxReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(report.title).font(Cypher.mono(16, weight: .bold)).foregroundStyle(Cypher.accent)
                Spacer()
                if !report.tx.txid.isEmpty {
                    Button { explorerCopy(report.tx.txid) } label: {
                        Image(systemName: "doc.on.doc")
                        Text("Copy txid")
                    }
                }
            }
            if !report.tx.txid.isEmpty {
                Text(report.tx.txid).font(Cypher.mono(12)).foregroundStyle(Cypher.text).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Text(report.status).font(Cypher.mono(11, weight: .semibold)).foregroundStyle(report.tx.confirmations > 0 ? AnyShapeStyle(Cypher.text) : AnyShapeStyle(Cypher.amber))
                if let height = report.height, report.tx.confirmations > 0 {
                    Button {
                        model.show(height: height)
                    } label: {
                        Image(systemName: "cube")
                        Text("Block \(height.withCommas)")
                    }
                }
            }
            if !report.categories.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.categories, id: \.name) { category in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            ExplorerTag(text: category.name)
                            Text(category.detail).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        }
                    }
                }
            }
        }
        .cypherPanel()
    }

    private func acceptanceBox(_ accept: TxReport.Acceptance, _ report: TxReport) -> some View {
        GroupBox(report.isPSBT ? "PSBT" : "Would your node accept it?") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(accept.lines, id: \.self) { line in
                    Text(line).font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                }
                if accept.reason == "txn-already-known" {
                    Text("Your node already knows this transaction: it's already been mined.")
                        .font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                    Button {
                        model.search(report.tx.txid)
                    } label: {
                        Image(systemName: "magnifyingglass")
                        Text("Find it in your node's blocks")
                    }
                } else if let allowed = accept.allowed {
                    Text(allowed ? "Your node would accept and relay it." : "Your node would reject it: \(accept.reason ?? "no reason given").")
                        .font(Cypher.mono(12, weight: .semibold))
                        .foregroundStyle(allowed ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(Cypher.amber))
                }
                Text("Nothing was broadcast.").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
            }
        }
    }

    private func mempoolBox(_ position: MempoolPosition, _ report: TxReport) -> some View {
        GroupBox("In your mempool") {
            VStack(alignment: .leading, spacing: 8) {
                ExplorerGrid {
                    ExplorerStat(title: "Own rate", value: ExplorerFormat.feeRate(position.ownRate))
                    ExplorerStat(title: "Effective rate", value: ExplorerFormat.feeRate(position.effectiveRate), note: "With parents and children")
                    if let time = position.firstSeen { ExplorerStat(title: "First seen", value: ExplorerFormat.ago(time)) }
                    ExplorerStat(title: "Replaceable", value: (position.isReplaceable ?? report.tx.signalsRBF) ? "Yes" : "No")
                }
                Text(report.inTemplate
                     ? "It's in the block your node would build right now."
                     : "It isn't in the block your node would build right now.")
                    .font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                linkRow("Waiting on", report.ancestors)
                linkRow("Spent by", report.descendants)
            }
        }
    }

    @ViewBuilder private func linkRow(_ title: String, _ txids: [String]) -> some View {
        if !txids.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.dim)
                ForEach(txids.prefix(10), id: \.self) { txid in
                    Button(ExplorerFormat.shortTxid(txid)) { model.open(.transaction(txid: txid, blockhash: nil, highlightedOutput: nil)) }
                        .buttonStyle(.plain).font(Cypher.mono(11)).foregroundStyle(Cypher.accent)
                }
                if txids.count > 10 { Text("And \(txids.count - 10) more.").font(Cypher.mono(10)).foregroundStyle(Cypher.dim) }
            }
        }
    }

    // MARK: - Details

    private func detailsBox(_ report: TxReport) -> some View {
        let tx = report.tx
        return GroupBox("Details") {
            ExplorerGrid {
                if let fee = tx.feeBtc {
                    ExplorerStat(title: "Fee", value: ExplorerFormat.btc(fee), note: tx.feeRate.map(ExplorerFormat.feeRate))
                }
                ExplorerStat(title: "Moved", value: ExplorerFormat.btc(tx.totalOutBtc), note: "Includes change")
                if let size = tx.size { ExplorerStat(title: "Size", value: ExplorerFormat.megabytes(size), note: "\(size.withCommas) bytes") }
                if let vsize = tx.vsize {
                    ExplorerStat(title: "Virtual size", value: "\(vsize.withCommas) vB", note: tx.weight.map { "\($0.withCommas) WU" })
                }
                if let saved = report.witnessSavings {
                    ExplorerStat(title: "Witness discount", value: String(format: "%.0f%% saved", saved), note: "Against the same bytes without it")
                }
                ForEach(report.fingerprints, id: \.title) { item in
                    ExplorerStat(title: item.title, value: item.value, note: item.note)
                }
            }
        }
    }

    private func privacyBox(_ report: TxReport) -> some View {
        let rating = report.rating(reused: reusedAddresses)
        return GroupBox("Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                if let rating = rating {
                    HStack(spacing: 8) {
                        Text("\(rating.grade.rawValue) · \(rating.score)/100")
                            .font(Cypher.mono(16, weight: .bold))
                            .foregroundStyle(rating.grade == .good ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(rating.grade == .fair ? Cypher.amber : Cypher.danger))
                    }
                    ForEach(rating.findings, id: \.text) { finding in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(finding.isGood ? "+" : "-").font(Cypher.mono(12, weight: .bold))
                                .foregroundStyle(finding.isGood ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(Cypher.amber))
                            Text(finding.text).font(Cypher.mono(11)).foregroundStyle(finding.isGood ? AnyShapeStyle(Cypher.dim) : AnyShapeStyle(Cypher.text))
                        }
                    }
                    deepCheck(report)
                    Text("Based on common on-chain assumptions. How it was broadcast matters too.")
                        .font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                } else if report.tx.isCoinbase {
                    Text("A coinbase spends nothing, so there's nothing to rate.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                } else {
                    Text("Your node couldn't find every input's address, and a rating of part of it would mislead.")
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    private var reusedAddresses: Set<String> {
        if case .done(let reused) = deep { return Set(reused.keys) }
        return []
    }

    /// No website can do this one privately: ask the node's own UTXO set about every address,
    /// without telling anyone which you're interested in.
    @ViewBuilder private func deepCheck(_ report: TxReport) -> some View {
        switch deep {
        case .notRun:
            Button {
                runDeepCheck(report)
            } label: {
                Image(systemName: "magnifyingglass")
                Text("Check these addresses for other coins")
            }
            .help("Scans your node's UTXO set, about a minute. Nothing leaves this Mac.")
        case .running(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress, total: 100).frame(width: 120)
                Text("Scanning your UTXO set…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                Button("Stop") {
                    deepTask?.cancel()
                    deep = .notRun
                }
            }
        case .done(let reused):
            if reused.isEmpty {
                Text("+ None of these addresses hold any other coins.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Holding other coins:").font(Cypher.mono(11, weight: .semibold)).foregroundStyle(Cypher.text)
                    ForEach(reused.keys.sorted(), id: \.self) { address in
                        Button("\(address): \((reused[address] ?? 0).withCommas) other coin\(reused[address] == 1 ? "" : "s")") { model.open(.address(address)) }
                            .buttonStyle(.plain).font(Cypher.mono(10)).foregroundStyle(Cypher.accent)
                    }
                }
            }
        case .failed(let message):
            Text(message).font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
        }
    }

    private func runDeepCheck(_ report: TxReport) {
        let tx = report.tx
        let addresses = Array(Set(tx.inputs.compactMap(\.address) + tx.outputs.compactMap(\.address))).prefix(100)
        let own = Set(tx.outputs.map { "\(tx.txid):\($0.n)" })
        deep = .running(0)
        deepTask = Task {
            do {
                let result = try await model.scan(addresses.map { "addr(\($0))" }) { percent in
                    await MainActor.run { if case .running = deep { deep = .running(percent) } }
                }
                var reused: [String: Int] = [:]
                for coin in result.coins where !own.contains(coin.id) {
                    if let address = coin.address, addresses.contains(address) { reused[address, default: 0] += 1 }
                }
                deep = .done(reused: reused)
            } catch is CancellationError {
                deep = .notRun
            } catch let failure as ExplorerError {
                if !Task.isCancelled { deep = .failed(failure.message) }
            } catch {
                deep = .notRun
            }
        }
    }

    // MARK: - Data

    private func embeddedBox(_ report: TxReport) -> some View {
        GroupBox("Embedded data") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(report.embedded.prefix(30).enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            ExplorerTag(text: item.name)
                            Text(locationText(item) + " · \(item.size.withCommas) bytes").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                        }
                        ForEach(item.details, id: \.title) { detail in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(detail.title.uppercased()).font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.dim).frame(width: 100, alignment: .leading)
                                Text(detail.value).font(Cypher.mono(11)).foregroundStyle(Cypher.text).textSelection(.enabled)
                            }
                        }
                    }
                }
                if report.embedded.count > 30 {
                    Text("And \(report.embedded.count - 30) more.").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                }
                Text("Matching a format says what the bytes look like. Nothing here checks a token is valid under its own rules.")
                    .font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
            }
        }
    }

    private func locationText(_ item: ExplorerEmbeddedData) -> String {
        switch item.location {
        case .output(let n): return "Output #\(n)"
        case .input(let n): return "Input #\(n)"
        }
    }

    // MARK: - Inputs and outputs

    private func inputsBox(_ report: TxReport) -> some View {
        GroupBox("Inputs · \(report.tx.inputs.count.withCommas)") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(report.tx.inputs.enumerated()), id: \.offset) { index, input in
                    Button { trace(input) } label: { inputRow(index, input, report) }
                        .buttonStyle(.plain)
                        .disabled(input.coinbase)
                    Rectangle().fill(Cypher.line.opacity(0.3)).frame(height: 1)
                }
            }
        }
    }

    private func inputRow(_ index: Int, _ input: ExplorerTx.Input, _ report: TxReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("#\(index)").font(Cypher.mono(10)).foregroundStyle(Cypher.dim).frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if input.coinbase {
                    Text("Coinbase: new coins and fees").font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                } else {
                    Text(input.address ?? input.txid.map { "\(ExplorerFormat.shortTxid($0)):\(input.vout ?? 0)" } ?? "Unknown")
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.text).lineLimit(1).truncationMode(.middle)
                    Text(inputNote(input, report)).font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                }
            }
            Spacer()
            Text(input.valueBtc.map(ExplorerFormat.btc) ?? (input.coinbase ? "" : "unknown amount")).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
            if !input.coinbase { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Cypher.dim) }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func inputNote(_ input: ExplorerTx.Input, _ report: TxReport) -> String {
        var parts = [ExplorerFormat.scriptName(input.scriptType)]
        if let source = input.sourceHeight {
            parts.append("from block \(source.withCommas)")
            if let height = report.height { parts.append(ExplorerFormat.age(blocks: max(height - source, 0)) + " old") }
        }
        if (input.sequence ?? .max) < 0xFFFFFFFE { parts.append("signals replace-by-fee") }
        return parts.joined(separator: " · ")
    }

    private func outputsBox(_ report: TxReport) -> some View {
        let rating = report.rating(reused: reusedAddresses)
        return GroupBox("Outputs · \(report.tx.outputs.count.withCommas)") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(report.tx.outputs, id: \.n) { output in
                    ExplorerOutputRow(tx: report.tx, output: output, height: report.height, isBroadcast: report.isBroadcast,
                                      isHighlighted: highlightedOutput == output.n,
                                      changeReason: rating?.likelyChange[report.payingIndex(output.n) ?? -1])
                        .id(output.n)
                    Rectangle().fill(Cypher.line.opacity(0.3)).frame(height: 1)
                }
            }
        }
    }

    private func trace(_ input: ExplorerTx.Input) {
        guard !input.coinbase, let txid = input.txid else { return }
        Task {
            var blockhash: String?
            if let height = input.sourceHeight, height > 0 { blockhash = try? await model.blockHash(height: height) }
            model.open(.transaction(txid: txid, blockhash: blockhash, highlightedOutput: input.vout))
        }
    }
}

/// One output: where it went, loaded when it scrolls into view.
private struct ExplorerOutputRow: View {
    let tx: ExplorerTx
    let output: ExplorerTx.Output
    let height: Int?
    let isBroadcast: Bool
    let isHighlighted: Bool
    let changeReason: String?
    @ObservedObject private var model = ExplorerModel.shared
    @State private var status: ExplorerModel.OutputStatus?
    @State private var searching: Int?
    @State private var spender: ExplorerModel.Spender?
    @State private var note: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("#\(output.n)").font(Cypher.mono(10)).foregroundStyle(Cypher.dim).frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if let address = output.address {
                    Button { model.open(.address(address)) } label: {
                        Text(address).font(Cypher.mono(11)).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain).foregroundStyle(Cypher.text)
                } else {
                    Text(ExplorerFormat.scriptName(output.scriptType)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                }
                HStack(spacing: 6) {
                    Text(ExplorerFormat.scriptName(output.scriptType)).font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                    if let changeReason = changeReason {
                        ExplorerTag(text: "LIKELY CHANGE").help(changeReason)
                    }
                    if let known = output.address.flatMap(ExplorerKnownAddress.note) {
                        ExplorerTag(text: known.name).help(known.detail)
                    }
                }
                statusLine
            }
            Spacer()
            Text(ExplorerFormat.btc(output.valueBtc)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, isHighlighted ? 6 : 0)
        .background(isHighlighted ? AnyShapeStyle(Cypher.accent.opacity(0.14)) : AnyShapeStyle(Color.clear))
        .task {
            guard isBroadcast, output.scriptType != "nulldata" else { return }
            status = await model.outputStatus(txid: tx.txid, n: output.n)
        }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder private var statusLine: some View {
        if let spender = spender {
            Button("Spent in block \(spender.height.withCommas) by \(ExplorerFormat.shortTxid(spender.txid))") {
                model.open(.transaction(txid: spender.txid, blockhash: spender.blockhash, highlightedOutput: nil))
            }
            .buttonStyle(.plain).font(Cypher.mono(10)).foregroundStyle(Cypher.accent)
        } else if let height = searching {
            HStack(spacing: 6) {
                Text("Looking in block \(height.withCommas)…").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                Button("Stop") {
                    task?.cancel()
                    searching = nil
                }
                .buttonStyle(.plain).font(Cypher.mono(10)).foregroundStyle(Cypher.accent)
            }
        } else if let note = note {
            Text(note).font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
        } else {
            switch status {
            case .unspent:
                Text("Unspent").font(Cypher.mono(10, weight: .semibold)).foregroundStyle(Cypher.accent)
            case .spentInMempool(let by):
                Button("Being spent by \(ExplorerFormat.shortTxid(by)), unconfirmed") {
                    model.open(.transaction(txid: by, blockhash: nil, highlightedOutput: nil))
                }
                .buttonStyle(.plain).font(Cypher.mono(10)).foregroundStyle(Cypher.amber)
            case .spent:
                Button {
                    findSpender()
                } label: {
                    Text("Spent · find where")
                        .font(Cypher.mono(10)).underline()
                }
                .buttonStyle(.plain).foregroundStyle(Cypher.accent)
                .help("Your node keeps no index of spends, but it can look through its own blocks quickly.")
            case nil:
                EmptyView()
            }
        }
    }

    private func findSpender() {
        guard let tip = model.tip else { return }
        // From the block it was created in: a coin can be spent in the same block.
        let first = max(height ?? 0, tip.pruneHeight ?? 0)
        let wasClipped = (tip.pruneHeight ?? 0) > (height ?? 0)
        searching = first
        let txid = tx.txid, vout = output.n
        task = Task {
            do {
                let found = try await model.findSpender(txid: txid, vout: vout, from: first, to: tip.height) { height in
                    await MainActor.run { if searching != nil { searching = height } }
                }
                searching = nil
                if let found = found {
                    spender = found
                } else {
                    note = wasClipped
                        ? "Spent, in a block your node has pruned (before \(first.withCommas))."
                        : "Spent, but not in the blocks up to \(tip.height.withCommas). A new block may have it."
                }
            } catch {
                searching = nil
            }
        }
    }
}

/// Inputs on the left, outputs on the right, the money flowing between them: each ribbon's width is
/// its share of the value. Long lists are summed into one "+N more" ribbon. Hover to read one.
struct ExplorerFlowView: View {
    let tx: ExplorerTx
    let onInput: (Int) -> Void
    @Environment(\.cypherPalette) private var palette
    @State private var hoverText: String?
    @State private var hovered: Int?

    private struct Band {
        let value: Double
        let kind: Kind
        let label: String
        enum Kind { case input(Int), output, rest, fee }
    }

    private static let maxBands = 24
    private static let gap: CGFloat = 3
    private static let barWidth: CGFloat = 12

    private var left: [Band] {
        let known = tx.inputsKnown && !tx.isCoinbase
        let share = max(tx.totalOutBtc, 0.00000001) / Double(max(tx.inputs.count, 1))
        var bands: [Band] = tx.inputs.prefix(Self.maxBands).enumerated().map { index, input in
            Band(value: known ? input.valueBtc ?? 0 : share, kind: .input(index),
                 label: "Input #\(index) · " + (input.coinbase ? "Coinbase" : (input.valueBtc.map(ExplorerFormat.btc) ?? "unknown amount")) + (input.address.map { " · \($0)" } ?? ""))
        }
        if tx.inputs.count > Self.maxBands {
            let rest = tx.inputs.dropFirst(Self.maxBands).reduce(0) { $0 + (known ? $1.valueBtc ?? 0 : share) }
            bands.append(Band(value: rest, kind: .rest, label: "+\(tx.inputs.count - Self.maxBands) more inputs"))
        }
        return bands
    }

    private var right: [Band] {
        var bands: [Band] = tx.outputs.prefix(Self.maxBands).map { output in
            Band(value: output.valueBtc, kind: .output,
                 label: "Output #\(output.n) · \(ExplorerFormat.btc(output.valueBtc))" + (output.address.map { " · \($0)" } ?? ""))
        }
        if tx.outputs.count > Self.maxBands {
            let rest = tx.outputs.dropFirst(Self.maxBands).reduce(0) { $0 + $1.valueBtc }
            bands.append(Band(value: rest, kind: .rest, label: "+\(tx.outputs.count - Self.maxBands) more outputs"))
        }
        if let fee = tx.feeBtc, fee > 0 {
            bands.append(Band(value: fee, kind: .fee, label: "Fee · \(ExplorerFormat.btc(fee))"))
        }
        return bands
    }

    /// Stacks the bands down `x`, heights by value with a small minimum so dust stays visible.
    private func stack(_ bands: [Band], x: CGFloat, height: CGFloat) -> [CGRect] {
        guard !bands.isEmpty else { return [] }
        let total = max(bands.reduce(0) { $0 + $1.value }, 0.00000001)
        let available = max(height - Self.gap * CGFloat(bands.count - 1), 1)
        let minimum = min(4, available / CGFloat(bands.count))
        let scaled = max(available - minimum * CGFloat(bands.count), 0)
        var y: CGFloat = 0
        return bands.map { band in
            let h = minimum + scaled * CGFloat(band.value / total)
            defer { y += h + Self.gap }
            return CGRect(x: x, y: y, width: Self.barWidth, height: h)
        }
    }

    private func color(_ band: Band) -> Color {
        switch band.kind {
        case .input: return palette.accent
        case .output: return Color(red: 0.25, green: 0.90, blue: 0.75)
        case .rest: return palette.dim
        case .fee: return Cypher.amber
        }
    }

    var body: some View {
        let left = self.left, right = self.right
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let leftRects = stack(left, x: 0, height: geometry.size.height)
                let rightRects = stack(right, x: geometry.size.width - Self.barWidth, height: geometry.size.height)
                Canvas { context, size in
                    // Everything passes through a narrow waist in the middle, the transaction itself.
                    let waistHeight = size.height * 0.55
                    let waistY = (size.height - waistHeight) / 2
                    let midX = size.width / 2
                    func ribbons(_ rects: [CGRect], _ bands: [Band], isLeft: Bool, offset: Int) {
                        let total = max(bands.reduce(0) { $0 + $1.value }, 0.00000001)
                        var y = waistY
                        for (index, frame) in rects.enumerated() {
                            let share = waistHeight * CGFloat(bands[index].value / total)
                            let edge = isLeft ? frame.maxX : frame.minX
                            let control = (edge + midX) / 2
                            var path = Path()
                            path.move(to: CGPoint(x: edge, y: frame.minY))
                            path.addCurve(to: CGPoint(x: midX, y: y), control1: CGPoint(x: control, y: frame.minY), control2: CGPoint(x: control, y: y))
                            path.addLine(to: CGPoint(x: midX, y: y + share))
                            path.addCurve(to: CGPoint(x: edge, y: frame.maxY), control1: CGPoint(x: control, y: y + share), control2: CGPoint(x: control, y: frame.maxY))
                            path.closeSubpath()
                            let isHot = hovered == index + offset
                            context.fill(path, with: .color(color(bands[index]).opacity(isHot ? 0.55 : 0.26)))
                            context.fill(Path(frame), with: .color(color(bands[index])))
                            y += share
                        }
                    }
                    ribbons(leftRects, left, isLeft: true, offset: 0)
                    ribbons(rightRects, right, isLeft: false, offset: 1000)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let point) = phase else {
                        hovered = nil
                        hoverText = nil
                        return
                    }
                    let isLeft = point.x < geometry.size.width / 2
                    let rects = isLeft ? leftRects : rightRects
                    let bands = isLeft ? left : right
                    if let index = rects.firstIndex(where: { point.y >= $0.minY - Self.gap && point.y <= $0.maxY + Self.gap }) {
                        hovered = index + (isLeft ? 0 : 1000)
                        hoverText = bands[index].label
                    }
                }
                .onTapGesture { point in
                    guard point.x < geometry.size.width / 2,
                          let index = leftRects.firstIndex(where: { point.y >= $0.minY - Self.gap && point.y <= $0.maxY + Self.gap }),
                          case .input(let input) = left[index].kind else { return }
                    onInput(input)
                }
            }
            Text(hoverText ?? "\(tx.inputs.count.withCommas) input\(tx.inputs.count == 1 ? "" : "s") to \(tx.outputs.count.withCommas) output\(tx.outputs.count == 1 ? "" : "s"). Hover to read, click an input to trace it.")
                .font(Cypher.mono(10)).foregroundStyle(Cypher.dim).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Everything worked out about one transaction.
struct TxReport {
    struct Acceptance {
        var lines: [String] = []
        var allowed: Bool?
        var reason: String?
    }

    struct Fingerprint {
        let title: String
        let value: String
        var note: String? = nil
    }

    var tx: ExplorerTx
    var raw: [String: Any]
    var height: Int?
    var embedded: [ExplorerEmbeddedData] = []
    var categories: [ExplorerTxCategory] = []
    var position: MempoolPosition?
    var ancestors: [String] = []
    var descendants: [String] = []
    var inTemplate = false
    var acceptance: Acceptance?
    var isPSBT = false
    /// In a block or a mempool, so its outputs mean something to ask about.
    var isBroadcast = true
    var isPasted = false

    var title: String {
        if isPSBT { return "UNSIGNED OR PART-SIGNED TRANSACTION" }
        if isPasted && !isBroadcast { return "TRANSACTION NOT BROADCAST" }
        return tx.isCoinbase ? "COINBASE TRANSACTION" : "TRANSACTION"
    }

    var status: String {
        if tx.confirmations > 0 { return "\(tx.confirmations.withCommas) confirmation\(tx.confirmations == 1 ? "" : "s")" + (tx.blocktime.map { " · \(ExplorerFormat.date($0))" } ?? "") }
        if isPSBT { return "Not broadcast" }
        if !isBroadcast { return "Pasted in, not in your mempool" }
        return "Unconfirmed"
    }

    /// Against the same transaction with every byte counted in full.
    var witnessSavings: Double? {
        guard let size = tx.size, let vsize = tx.vsize, size > vsize, size > 0 else { return nil }
        return (1 - Double(vsize) / Double(size)) * 100
    }

    /// What a wallet leaves on a transaction without meaning to.
    var fingerprints: [Fingerprint] {
        var items: [Fingerprint] = []
        if let version = tx.version { items.append(Fingerprint(title: "Version", value: String(version))) }
        if let locktime = tx.locktime {
            if locktime == 0 {
                items.append(Fingerprint(title: "Locktime", value: "None"))
            } else if locktime < 500_000_000 {
                let isRecent = height.map { abs($0 - locktime) <= 110 } ?? false
                items.append(Fingerprint(title: "Locktime", value: "Block \(locktime.withCommas)", note: isRecent ? "Anti fee sniping, as some wallets do" : nil))
            } else {
                items.append(Fingerprint(title: "Locktime", value: ExplorerFormat.date(locktime)))
            }
        }
        if !tx.isCoinbase { items.append(Fingerprint(title: "Replace by fee", value: tx.signalsRBF ? "Signals it" : "Doesn't signal")) }
        return items
    }

    /// Where an output sits among those that pay someone, which is how the rating counts them.
    func payingIndex(_ n: Int) -> Int? {
        guard tx.outputs.contains(where: { $0.n == n && $0.address != nil }) else { return nil }
        return tx.outputs.firstIndex { $0.n == n }
    }

    /// Only when every input's address is known: a rating of part of it would mislead.
    func rating(reused: Set<String>) -> TransactionPrivacyRating? {
        guard !tx.isCoinbase else { return nil }
        let inputs = tx.inputs.compactMap { input in input.address.map { (address: $0, type: input.scriptType) } }
        guard !inputs.isEmpty, inputs.count == tx.inputs.count else { return nil }
        return TransactionPrivacyRating(inputs: inputs, outputs: tx.outputs.map { (address: $0.address, amountBtc: $0.valueBtc, type: $0.scriptType) }, reused: reused)
    }

    @MainActor
    static func load(_ source: ExplorerTransactionView.Source, model: ExplorerModel) async throws -> TxReport {
        var report: TxReport
        switch source {
        case .txid(let txid, let blockhash):
            let raw = try await model.transaction(txid: txid, blockhash: blockhash)
            guard let tx = ExplorerTx(raw: raw) else { throw ExplorerError("The node's reply didn't make sense.") }
            report = TxReport(tx: tx, raw: raw)
        case .pasted(let input):
            report = try await pasted(input)
        }
        let tipHeight: Int?
        if let tip = model.tip { tipHeight = tip.height } else { tipHeight = (try? await model.fetchTip())?.height }
        // Its block says exactly: the tip may have moved since it was last asked.
        if report.tx.confirmations > 0, let hash = report.tx.blockhash,
           let header = try? await ExplorerRPC.call("getblockheader", ["blockhash": hash]) as? [String: Any],
           let height = RPCValue.int(header["height"]) {
            report.height = height
        } else if report.tx.confirmations > 0, let tipHeight = tipHeight {
            report.height = tipHeight - report.tx.confirmations + 1
        } else {
            report.height = tipHeight.map { $0 + 1 }
        }
        report.tx = await model.fillInputs(report.tx, tipHeight: tipHeight)
        await report.loadMempool(model: model)
        report.embedded = ExplorerEmbeddedData.decode(raw: report.raw)
        report.categories = ExplorerTxCategory.all(tx: report.tx, embedded: report.embedded, height: report.height)
        return report
    }

    @MainActor private mutating func loadMempool(model: ExplorerModel) async {
        guard tx.confirmations == 0, !tx.txid.isEmpty else { return }
        guard let entry = try? await ExplorerRPC.call("getmempoolentry", ["txid": tx.txid]) as? [String: Any],
              let position = MempoolPosition(entry: entry) else {
            if isPasted { isBroadcast = false }
            return
        }
        self.position = position
        isBroadcast = true
        if tx.feeBtc == nil { tx.feeBtc = RPCValue.double((entry["fees"] as? [String: Any])?["base"]) }
        inTemplate = model.template.contains { $0.txid == tx.txid }
        ancestors = ((try? await ExplorerRPC.call("getmempoolancestors", ["txid": tx.txid])) as? [Any])?.compactMap { $0 as? String } ?? []
        descendants = ((try? await ExplorerRPC.call("getmempooldescendants", ["txid": tx.txid])) as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private init(tx: ExplorerTx, raw: [String: Any]) {
        self.tx = tx
        self.raw = raw
    }

    private static func pasted(_ input: String) async throws -> TxReport {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("cHNidP") { return try await psbt(text) }
        guard let raw = try await ExplorerRPC.call("decoderawtransaction", ["hexstring": text]) as? [String: Any],
              let tx = ExplorerTx(raw: raw) else {
            throw ExplorerError("That doesn't decode as a transaction.")
        }
        var report = TxReport(tx: tx, raw: raw)
        report.isPasted = true
        // Is it in the chain or mempool already?
        if let known = try? await ExplorerRPC.call("getrawtransaction", ["txid": tx.txid, "verbosity": 2]) as? [String: Any], let found = ExplorerTx(raw: known) {
            report.tx = found
            report.raw = known
            return report
        }
        report.isBroadcast = false
        if let results = try? await ExplorerRPC.call("testmempoolaccept", ["rawtxs": [text]]) as? [[String: Any]], let first = results.first {
            var acceptance = Acceptance()
            acceptance.allowed = first["allowed"] as? Bool
            acceptance.reason = RPCValue.string(first["reject-reason"])
            report.acceptance = acceptance
        }
        return report
    }

    /// A version 2 PSBT (what Core 32 makes) has no transaction inside: its parts are spread over
    /// its inputs and outputs. Put back together in the same shape, with no txid until it's built.
    private static func version2Transaction(_ decoded: [String: Any]) -> [String: Any]? {
        guard let inputs = decoded["inputs"] as? [[String: Any]], let outputs = decoded["outputs"] as? [[String: Any]] else { return nil }
        var raw: [String: Any] = ["txid": ""]
        raw["version"] = decoded["tx_version"]
        raw["locktime"] = decoded["fallback_locktime"] ?? 0
        raw["vin"] = inputs.map { input -> [String: Any] in
            ["txid": input["previous_txid"] as Any, "vout": input["previous_vout"] as Any, "sequence": input["sequence"] ?? 0xFFFFFFFF]
        }
        raw["vout"] = outputs.enumerated().map { index, output -> [String: Any] in
            ["n": index, "value": output["amount"] as Any, "scriptPubKey": output["script"] as Any]
        }
        return raw
    }

    /// A PSBT carries what its inputs spend, so nothing need be on-chain to read one.
    private static func psbt(_ text: String) async throws -> TxReport {
        guard let decoded = try await ExplorerRPC.call("decodepsbt", ["psbt": text]) as? [String: Any],
              let raw = (decoded["tx"] as? [String: Any]) ?? version2Transaction(decoded), var tx = ExplorerTx(raw: raw) else {
            throw ExplorerError("That doesn't decode as a PSBT.")
        }
        for (index, input) in ((decoded["inputs"] as? [[String: Any]]) ?? []).enumerated() where index < tx.inputs.count {
            if let utxo = input["witness_utxo"] as? [String: Any] {
                let script = utxo["scriptPubKey"] as? [String: Any]
                tx.inputs[index].valueBtc = RPCValue.double(utxo["amount"])
                tx.inputs[index].address = RPCValue.string(script?["address"])
                tx.inputs[index].scriptType = RPCValue.string(script?["type"])
            } else if let previous = input["non_witness_utxo"] as? [String: Any], let vout = tx.inputs[index].vout,
                      let output = ExplorerTx(raw: previous)?.outputs.first(where: { $0.n == vout }) {
                tx.inputs[index].valueBtc = output.valueBtc
                tx.inputs[index].address = output.address
                tx.inputs[index].scriptType = output.scriptType
            }
        }
        tx.feeBtc = RPCValue.double(decoded["fee"]) ?? tx.feeBtc
        var report = TxReport(tx: tx, raw: raw)
        report.isPSBT = true
        report.isPasted = true
        report.isBroadcast = false
        var acceptance = Acceptance()
        if let analysis = try? await ExplorerRPC.call("analyzepsbt", ["psbt": text]) as? [String: Any] {
            let missing = ((analysis["inputs"] as? [[String: Any]]) ?? []).reduce(0) {
                $0 + ((($1["missing"] as? [String: Any])?["signatures"] as? [Any])?.count ?? 0)
            }
            switch RPCValue.string(analysis["next"]) {
            case "creator": acceptance.lines.append("Next step: creating it.")
            case "updater": acceptance.lines.append("Next step: adding its inputs' details.")
            case "signer": acceptance.lines.append("Next step: signing." + (missing > 0 ? " Missing \(missing) signature\(missing == 1 ? "" : "s")." : ""))
            case "finalizer": acceptance.lines.append("Fully signed: ready to finalize.")
            case "extractor": acceptance.lines.append("Finalized: ready to broadcast.")
            case let other?: acceptance.lines.append("Next step: \(other).")
            case nil: break
            }
            if let error = RPCValue.string(analysis["error"]) { acceptance.lines.append("Problem: \(error)") }
            if let vsize = RPCValue.int(analysis["estimated_vsize"]) { acceptance.lines.append("About \(vsize.withCommas) vB once signed.") }
            if let rate = RPCValue.double(analysis["estimated_feerate"]) { acceptance.lines.append("About \(ExplorerFormat.feeRate(rate * 100_000)) once signed.") }
        }
        report.acceptance = acceptance
        return report
    }
}
