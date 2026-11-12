//
//  ExplorerBlockDetailView.swift
//  FullyNoded-Server
//
//  One block, read whole: every transaction's fee, age and category, what data it carries, and how
//  it compares with what this node had in its mempool. The block map is every transaction at once,
//  its area by size and its colour by fee rate.
//

import SwiftUI

/// Small reusable pieces of the explorer's pages.
struct ExplorerStat: View {
    let title: String
    let value: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.dim)
            Text(value).font(Cypher.mono(13, weight: .semibold)).foregroundStyle(Cypher.text).textSelection(.enabled)
            if let note = note {
                Text(note).font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExplorerGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 12) {
            content
        }
    }
}

struct ExplorerBar: View {
    let title: String
    let value: String
    let share: Double
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Cypher.mono(11)).foregroundStyle(Cypher.text).frame(width: 120, alignment: .leading).lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Cypher.line.opacity(0.25))
                    Rectangle().fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Cypher.accent))
                        .frame(width: max(geometry.size.width * min(share, 1), share > 0 ? 2 : 0))
                }
            }
            .frame(height: 8)
            Text(value).font(Cypher.mono(10)).foregroundStyle(Cypher.dim).frame(width: 120, alignment: .trailing).lineLimit(1)
        }
    }
}

struct ExplorerTag: View {
    let text: String
    var isOn = false
    var body: some View {
        Text(text)
            .font(Cypher.mono(10, weight: .bold))
            .foregroundStyle(isOn ? AnyShapeStyle(Cypher.bg) : AnyShapeStyle(Cypher.accent))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(isOn ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(Color.clear))
            .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
    }
}

func explorerCopy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct ExplorerBlockDetailView: View {
    let height: Int
    @ObservedObject private var model = ExplorerModel.shared
    @State private var digest: BlockDigest?
    @State private var error: String?
    @State private var category: String?
    @State private var filter = ""
    @State private var sort = Sort.position

    enum Sort: String, CaseIterable {
        case position = "Block order", feeRate = "Fee rate", size = "Size", value = "Value", age = "Oldest coins"
    }

    private var summary: ExplorerBlockSummary? { model.summaries[height] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                title
                if let digest = digest {
                    overview(digest)
                    if let arrival = model.arrivals[digest.hash] { arrivalBox(arrival) }
                    contents(digest)
                    // A coinbase alone has nothing to map.
                    if digest.txs.count > 1 {
                        GroupBox("Block map") { ExplorerBlockMap(digest: digest, highlight: highlight, onSelect: openTx) }
                    }
                    transactionList(digest)
                } else if let error = error {
                    GroupBox("This block") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(height < (model.tip?.pruneHeight ?? 0)
                                 ? "Your node has pruned this block's data, so only its header is left."
                                 : error)
                                .font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                            if let summary = summary {
                                ExplorerGrid {
                                    ExplorerStat(title: "Time", value: ExplorerFormat.date(summary.time))
                                    ExplorerStat(title: "Transactions", value: summary.txCount.withCommas)
                                    if let hash = summary.hash { ExplorerStat(title: "Hash", value: ExplorerFormat.shortTxid(hash)) }
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.6)
                        Text("Reading the whole block…").font(Cypher.mono(12)).foregroundStyle(Cypher.dim)
                    }
                }
            }
            .padding(16)
        }
        .task {
            model.requestSummary(height)
            do {
                let hash = try await model.blockHash(height: height)
                // A moment first if it means reading the whole block, so going past blocks
                // quickly doesn't read each one. Moving on cancels this.
                if !model.hasDigest(hash: hash) {
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                digest = try await model.digest(hash: hash)
            } catch let failure as ExplorerError {
                error = failure.message
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var title: some View {
        HStack(spacing: 10) {
            Text("BLOCK \(height.withCommas)").font(Cypher.mono(18, weight: .bold)).foregroundStyle(Cypher.accent)
            Button { model.selectedHeight = height - 1 } label: { Image(systemName: "chevron.left") }
                .disabled(height == 0).help("Older block")
            Button { model.selectedHeight = height + 1 } label: { Image(systemName: "chevron.right") }
                .disabled(height >= (model.tip?.height ?? 0)).help("Newer block")
            if let digest = digest, digest.isSolo { ExplorerTag(text: "SOLO WIN", isOn: true) }
            Spacer()
            if let hash = digest?.hash ?? summary?.hash {
                Text(ExplorerFormat.shortTxid(hash)).font(Cypher.mono(11)).foregroundStyle(Cypher.dim).textSelection(.enabled)
                Button { explorerCopy(hash) } label: { Image(systemName: "doc.on.doc") }.help("Copy the block's hash")
            }
        }
    }

    private func overview(_ digest: BlockDigest) -> some View {
        GroupBox("Overview") {
            ExplorerGrid {
                ExplorerStat(title: "Mined", value: ExplorerFormat.ago(digest.time), note: ExplorerFormat.date(digest.time))
                ExplorerStat(title: "Miner", value: digest.miner ?? "Unknown", note: digest.coinbaseText.map { "“\($0.prefix(60))”" })
                ExplorerStat(title: "Transactions", value: digest.txs.count.withCommas,
                             note: "\(digest.inputCount.withCommas) inputs · \(digest.outputCount.withCommas) outputs")
                ExplorerStat(title: "Size", value: ExplorerFormat.megabytes(digest.size),
                             note: String(format: "%.1f%% witness data", Double(digest.witnessBytes) / Double(max(digest.size, 1)) * 100))
                ExplorerStat(title: "Weight", value: String(format: "%.3f MWU", Double(digest.weight) / 1e6),
                             note: String(format: "%.1f%% full", Double(digest.weight) / Double(ExplorerBlockSummary.maxWeight) * 100))
                ExplorerStat(title: "Moved", value: ExplorerFormat.btc(digest.totalOutBtc), note: "Includes change")
                if let fees = digest.feesSats {
                    ExplorerStat(title: "Fees", value: ExplorerFormat.btc(sats: fees),
                                 note: digest.subsidySats.map { String(format: "%.2f%% of the reward", Double(fees) / Double(max($0 + fees, 1)) * 100) })
                }
                if let subsidy = digest.subsidySats, let fees = digest.feesSats {
                    ExplorerStat(title: "Reward", value: ExplorerFormat.btc(sats: subsidy + fees), note: digest.payoutAddress.map { "To \(ExplorerFormat.shortTxid($0))" })
                }
                if digest.feePercentiles.count == 5 {
                    ExplorerStat(title: "Median fee", value: ExplorerFormat.feeRate(digest.feePercentiles[2]),
                                 note: "\(ExplorerFormat.feeRate(digest.feePercentiles[0])) to \(ExplorerFormat.feeRate(digest.feePercentiles[4]))")
                }
                if let confirmations = digest.confirmations { ExplorerStat(title: "Confirmations", value: confirmations.withCommas) }
                if let days = digest.coinDaysDestroyed {
                    ExplorerStat(title: "Coin days destroyed", value: Int(days).withCommas, note: "BTC × days each coin sat still")
                }
                if let difficulty = digest.difficulty {
                    ExplorerStat(title: "Difficulty", value: difficulty >= 1e12 ? String(format: "%.2f T", difficulty / 1e12) : String(format: "%.0f", difficulty),
                                 note: digest.nonce.map { "Nonce \($0)" })
                }
            }
        }
    }

    /// Something only a node watching at the moment of arrival can know.
    private func arrivalBox(_ arrival: BlockArrival) -> some View {
        GroupBox("Compared with your mempool") {
            VStack(alignment: .leading, spacing: 6) {
                ExplorerBar(title: "Already seen", value: "\(arrival.known.withCommas) of \(arrival.txCount.withCommas)",
                            share: Double(arrival.known) / Double(max(arrival.txCount, 1)))
                if let share = arrival.templateShare {
                    ExplorerBar(title: "Your next block", value: String(format: "%.0f%% included", share * 100), share: share)
                }
                Text(arrival.surprises == 0
                     ? "Your node had already seen every transaction in this block."
                     : "\(arrival.surprises.withCommas) transaction\(arrival.surprises == 1 ? " was" : "s were") new to your node when the block arrived: sent in the last few seconds, or kept private by the miner.")
                    .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                if arrival.leftOut > 0 {
                    Text("The miner left out \(arrival.leftOut.withCommas) transaction\(arrival.leftOut == 1 ? "" : "s") your node would have included.")
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    private func contents(_ digest: BlockDigest) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GroupBox("What's in it") {
                VStack(alignment: .leading, spacing: 8) {
                    if digest.categoryCounts.isEmpty {
                        Text("Nothing stands out.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    }
                    FlowChips(items: digest.categoryCounts.map { ($0.name, "\($0.name) · \($0.count.withCommas)") }, selected: $category)
                    if digest.dataBytes > 0 {
                        Text("\(ExplorerFormat.size(digest.dataBytes)) of embedded data, " + String(format: "%.1f%% of the block", Double(digest.dataBytes) / Double(max(digest.size, 1)) * 100))
                            .font(Cypher.mono(11, weight: .semibold)).foregroundStyle(Cypher.text).padding(.top, 4)
                        ForEach(digest.dataByName.prefix(6), id: \.name) { item in
                            ExplorerBar(title: item.name, value: "\(ExplorerFormat.size(item.bytes)) · \(item.count.withCommas)",
                                        share: Double(item.bytes) / Double(max(digest.dataBytes, 1)))
                        }
                    }
                    if let oldest = digest.oldestInput {
                        Button {
                            openTx(oldest.txid)
                        } label: {
                            Text("Oldest coin spent: from block \(oldest.height.withCommas), \(ExplorerFormat.age(blocks: digest.height - oldest.height)) old")
                                .font(Cypher.mono(11)).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Cypher.accent)
                    }
                }
            }
            GroupBox("Address types") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Outputs").font(Cypher.mono(10, weight: .bold)).foregroundStyle(Cypher.dim)
                    shares(digest.outputScripts, total: digest.outputCount)
                    if !digest.inputScripts.isEmpty {
                        Text("Spent").font(Cypher.mono(10, weight: .bold)).foregroundStyle(Cypher.dim).padding(.top, 4)
                        shares(digest.inputScripts, total: digest.inputCount)
                    }
                }
            }
        }
    }

    private func shares(_ items: [ScriptShare], total: Int) -> some View {
        ForEach(items.prefix(6)) { item in
            ExplorerBar(title: item.name, value: String(format: "%.1f%% · %@", Double(item.count) / Double(max(total, 1)) * 100, item.count.withCommas),
                        share: Double(item.count) / Double(max(total, 1)))
        }
    }

    private var highlight: ((DigestTx) -> Bool)? {
        let text = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard category != nil || !text.isEmpty else { return nil }
        return { tx in
            (category.map(tx.categories.contains) ?? true)
                && (text.isEmpty || tx.txid.hasPrefix(text) || tx.addresses.contains { $0.lowercased().contains(text) })
        }
    }

    private func transactionList(_ digest: BlockDigest) -> some View {
        let shown = sorted(digest.txs.filter { highlight?($0) ?? true })
        return GroupBox("Transactions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Filter by txid or address", text: $filter)
                        .textFieldStyle(.plain).font(Cypher.mono(11))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 190)
                    Text("\(shown.count.withCommas) of \(digest.txs.count.withCommas)").font(Cypher.mono(10)).foregroundStyle(Cypher.dim).fixedSize()
                }
                LazyVStack(spacing: 0) {
                    ForEach(shown.prefix(1000)) { tx in
                        Button { openTx(tx.txid) } label: { ExplorerTxRow(tx: tx) }.buttonStyle(.plain)
                        Rectangle().fill(Cypher.line.opacity(0.3)).frame(height: 1)
                    }
                }
                if shown.count > 1000 {
                    Text("Showing the first 1,000. Filter to narrow it down.").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    private func sorted(_ txs: [DigestTx]) -> [DigestTx] {
        switch sort {
        case .position: return txs
        case .feeRate: return txs.sorted { ($0.feeRate ?? -1) > ($1.feeRate ?? -1) }
        case .size: return txs.sorted { $0.vsize > $1.vsize }
        case .value: return txs.sorted { $0.totalOutBtc > $1.totalOutBtc }
        case .age: return txs.sorted { ($0.oldestInputHeight ?? .max) < ($1.oldestInputHeight ?? .max) }
        }
    }

    private func openTx(_ txid: String) {
        model.open(.transaction(txid: txid, blockhash: digest?.hash, highlightedOutput: nil))
    }
}

/// Toggle chips that wrap.
struct FlowChips: View {
    let items: [(id: String, title: String)]
    @Binding var selected: String?

    var body: some View {
        ExplorerWrap(spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button {
                    selected = selected == item.id ? nil : item.id
                } label: {
                    ExplorerTag(text: item.title, isOn: selected == item.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Lays its children in rows, wrapping at the width it's offered.
struct ExplorerWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(width: proposal.width ?? 500, subviews: subviews)
        return CGSize(width: proposal.width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x)
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}

private struct ExplorerTxRow: View {
    let tx: DigestTx

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(ExplorerFeeColor.color(tx.feeRate)).frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ExplorerFormat.shortTxid(tx.txid)).font(Cypher.mono(11, weight: .semibold)).foregroundStyle(Cypher.text)
                    if tx.isCoinbase { ExplorerTag(text: "COINBASE") }
                    ForEach(tx.categories.prefix(3), id: \.self) { ExplorerTag(text: $0) }
                }
                Text("\(tx.inputCount) in · \(tx.outputCount) out · \(ExplorerFormat.megabytes(tx.size))")
                    .font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ExplorerFormat.btc(tx.totalOutBtc)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                Text(tx.feeRate.map(ExplorerFormat.feeRate) ?? "").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

/// Every transaction at once: area by size, colour by fee rate. Hover to read one, click to open it.
struct ExplorerBlockMap: View {
    let digest: BlockDigest
    let highlight: ((DigestTx) -> Bool)?
    let onSelect: (String) -> Void
    @State private var hovered: DigestTx?
    @State private var rects: [CGRect] = []
    @State private var laidOutWidth: CGFloat = 0

    private static let height: CGFloat = 300

    var body: some View {
        let txs = digest.txsBySize
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                Canvas { context, _ in
                    for (index, rect) in rects.enumerated() where index < txs.count {
                        let tx = txs[index]
                        let dimmed = highlight.map { !$0(tx) } ?? false
                        context.fill(Path(rect.insetBy(dx: 0.25, dy: 0.25)),
                                     with: .color(ExplorerFeeColor.color(tx.feeRate).opacity(dimmed ? 0.1 : (hovered?.txid == tx.txid ? 1 : 0.8))))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if let index = rects.firstIndex(where: { $0.contains(point) }), index < txs.count { hovered = txs[index] }
                    case .ended:
                        hovered = nil
                    }
                }
                .onTapGesture { point in
                    if let index = rects.firstIndex(where: { $0.contains(point) }), index < txs.count { onSelect(txs[index].txid) }
                }
                .onAppear { layout(width: geometry.size.width, txs) }
                .onChange(of: geometry.size.width) { _, width in layout(width: width, txs) }
            }
            .frame(height: Self.height)
            HStack(spacing: 4) {
                Text("sat/vB").font(Cypher.mono(9)).foregroundStyle(Cypher.dim)
                ForEach(ExplorerFeeColor.buckets, id: \.label) { bucket in
                    Rectangle().fill(bucket.color).frame(width: 12, height: 8)
                    Text(bucket.label).font(Cypher.mono(9)).foregroundStyle(Cypher.dim)
                }
                Spacer()
                if let tx = hovered {
                    Text("\(ExplorerFormat.shortTxid(tx.txid)) · \(tx.feeRate.map(ExplorerFormat.feeRate) ?? "coinbase") · \(tx.vsize.withCommas) vB\(tx.categories.first.map { " · \($0)" } ?? "")")
                        .font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                }
            }
        }
    }

    private func layout(width: CGFloat, _ txs: [DigestTx]) {
        guard width > 0, width != laidOutWidth else { return }
        laidOutWidth = width
        rects = ExplorerTreemap.layout(areas: txs.map { Double($0.vsize) }, in: CGSize(width: width, height: Self.height))
    }
}
