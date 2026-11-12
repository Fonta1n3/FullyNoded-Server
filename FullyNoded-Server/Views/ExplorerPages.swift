//
//  ExplorerPages.swift
//  FullyNoded-Server
//
//  The explorer's other pages: the mempool, the chain's vitals, pasting a transaction in, famous
//  coins and blocks, an address, and your own coins by block.
//

import SwiftUI
import Charts

// MARK: - Mempool

struct ExplorerMempoolTab: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var digest: MempoolDigest?
    @State private var error: String?
    @State private var estimates: [Int: Double] = [:]

    private static let targets: [(blocks: Int, name: String)] = [(1, "Next block"), (3, "30 minutes"), (6, "1 hour"), (144, "1 day"), (1008, "1 week")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let digest = digest {
                    GroupBox("Your node's mempool") {
                        ExplorerGrid {
                            ExplorerStat(title: "Transactions", value: digest.count.withCommas)
                            ExplorerStat(title: "Size", value: String(format: "%.2f MvB", Double(digest.vsize) / 1e6),
                                         note: "About \(Int((Double(digest.vsize) / Double(MempoolDigest.blockVSize)).rounded(.up))) blocks' worth")
                            ExplorerStat(title: "Fees waiting", value: ExplorerFormat.btc(sats: digest.feesSats))
                            if let replaceable = digest.replaceableCount, digest.count > 0 {
                                ExplorerStat(title: "Signal replace by fee", value: String(format: "%.0f%%", Double(replaceable) / Double(digest.count) * 100))
                            }
                            if let oldest = digest.oldestTime { ExplorerStat(title: "Longest waiting", value: ExplorerFormat.ago(oldest)) }
                            if let minimum = RPCValue.double(model.mempoolInfo["mempoolminfee"]) {
                                ExplorerStat(title: "Minimum to enter", value: ExplorerFormat.feeRate(minimum * 100_000))
                            }
                        }
                    }
                    if !digest.blocks.isEmpty { projected(digest) }
                    HStack(alignment: .top, spacing: 14) {
                        histogram(digest)
                        estimatesBox
                    }
                    if !model.template.isEmpty { templateBox }
                    topBox(digest)
                } else if let error = error {
                    Text(error).font(Cypher.mono(12)).foregroundStyle(Cypher.amber)
                } else {
                    Text("Reading your mempool…").font(Cypher.mono(12)).foregroundStyle(Cypher.dim)
                }
            }
            .padding(16)
        }
        .task {
            // Once a minute: a verbose getrawmempool is heavy on a full mempool.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func load() async {
        do {
            guard let pool = try await ExplorerRPC.call("getrawmempool", ["verbose": true], timeout: 60) as? [String: Any] else { return }
            digest = await Task.detached(priority: .userInitiated) { MempoolDigest.make(pool: pool) }.value
            error = nil
        } catch let failure as ExplorerError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
        for target in Self.targets {
            if let response = try? await ExplorerRPC.call("estimatesmartfee", ["conf_target": target.blocks]) as? [String: Any],
               let rate = RPCValue.double(response["feerate"]) {
                estimates[target.blocks] = rate * 100_000
            }
        }
    }

    /// Best payers first, a block at a time, if nothing else arrived. A rough picture: new
    /// transactions keep jumping in, and packages can reorder things.
    private func projected(_ digest: MempoolDigest) -> some View {
        GroupBox("Next blocks, if nothing else arrives") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(digest.blocks.prefix(12)) { block in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("+\(block.index + 1)").font(Cypher.mono(13, weight: .bold)).foregroundStyle(Cypher.accent)
                            Text("~\(ExplorerFormat.feeRate(block.medianRate))").font(Cypher.mono(11, weight: .semibold)).foregroundStyle(Cypher.text)
                            Text(String(format: "%.1f–%.1f", block.lowRate, block.highRate)).font(Cypher.mono(9)).foregroundStyle(Cypher.dim)
                            Spacer(minLength: 2)
                            Text("\(block.txCount.withCommas) txs").font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                            Text(ExplorerFormat.btcShort(Double(block.feeSats) / 1e8) + " fees").font(Cypher.mono(9)).foregroundStyle(Cypher.dim)
                        }
                        .padding(8)
                        .frame(width: 118, height: 112, alignment: .topLeading)
                        .background(alignment: .bottom) {
                            GeometryReader { geometry in
                                Rectangle().fill(ExplorerFeeColor.color(block.medianRate).opacity(0.3))
                                    .frame(height: geometry.size.height * min(Double(block.vsize) / Double(MempoolDigest.blockVSize), 1))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
                    }
                    if digest.blocks.count > 12 {
                        Text("+\(digest.blocks.count - 12) more").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func histogram(_ digest: MempoolDigest) -> some View {
        GroupBox("Waiting, by fee rate") {
            let largest = max(digest.buckets.map(\.vsize).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(digest.buckets.reversed()) { bucket in
                    ExplorerBar(title: "\(bucket.label) sat/vB", value: "\(String(format: "%.2f MvB", Double(bucket.vsize) / 1e6)) · \(bucket.count.withCommas)",
                                share: Double(bucket.vsize) / Double(largest), color: ExplorerFeeColor.color(bucket.from))
                }
            }
        }
    }

    private var estimatesBox: some View {
        GroupBox("Your node's fee estimates") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.targets, id: \.blocks) { target in
                    HStack {
                        Text(target.name).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        Spacer()
                        Text(estimates[target.blocks].map(ExplorerFormat.feeRate) ?? "no estimate yet").font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                    }
                }
                if let lowest = model.template.map(\.feeRate).min() {
                    Rectangle().fill(Cypher.line.opacity(0.4)).frame(height: 1)
                    HStack {
                        Text("Lowest in your next block").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        Spacer()
                        Text(ExplorerFormat.feeRate(lowest)).font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                    }
                }
            }
        }
        .frame(maxWidth: 380)
    }

    private var templateBox: some View {
        GroupBox("The block your node would build now") {
            ExplorerTemplateMap(txs: model.template, revision: model.templateRevision) { txid in
                model.open(.transaction(txid: txid, blockhash: nil, highlightedOutput: nil))
            }
        }
    }

    private func topBox(_ digest: MempoolDigest) -> some View {
        GroupBox("Paying the most") {
            LazyVStack(spacing: 0) {
                ForEach(digest.top) { entry in
                    Button {
                        model.open(.transaction(txid: entry.txid, blockhash: nil, highlightedOutput: nil))
                    } label: {
                        HStack(spacing: 10) {
                            Rectangle().fill(ExplorerFeeColor.color(entry.rate)).frame(width: 4, height: 16)
                            Text(ExplorerFormat.shortTxid(entry.txid)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                            Spacer()
                            Text(ExplorerFormat.feeRate(entry.rate)).font(Cypher.mono(11, weight: .semibold)).foregroundStyle(Cypher.text)
                            Text("\(entry.vsize.withCommas) vB").font(Cypher.mono(10)).foregroundStyle(Cypher.dim).frame(width: 90, alignment: .trailing)
                            Text(ExplorerFormat.ago(entry.time)).font(Cypher.mono(10)).foregroundStyle(Cypher.dim).frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The node's next block: area by size, colour by fee rate.
private struct ExplorerTemplateMap: View {
    let txs: [TemplateTx]
    let revision: Int
    let onSelect: (String) -> Void
    @State private var hovered: TemplateTx?
    // Worked out when something changes, not on each mouse move.
    @State private var sorted: [TemplateTx] = []
    @State private var rects: [CGRect] = []

    private func layout(_ size: CGSize) {
        sorted = txs.sorted { $0.vsize > $1.vsize }
        rects = ExplorerTreemap.layout(areas: sorted.map { Double($0.vsize) }, in: size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                Canvas { context, _ in
                    for (index, rect) in rects.enumerated() where index < sorted.count {
                        context.fill(Path(rect.insetBy(dx: 0.25, dy: 0.25)), with: .color(ExplorerFeeColor.color(sorted[index].feeRate).opacity(hovered?.txid == sorted[index].txid ? 1 : 0.8)))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let point) = phase, let index = rects.firstIndex(where: { $0.contains(point) }), index < sorted.count {
                        hovered = sorted[index]
                    } else if case .ended = phase {
                        hovered = nil
                    }
                }
                .onTapGesture { point in
                    if let index = rects.firstIndex(where: { $0.contains(point) }), index < sorted.count { onSelect(sorted[index].txid) }
                }
                .onAppear { layout(geometry.size) }
                .onChange(of: geometry.size) { _, size in layout(size) }
                .onChange(of: revision) { _, _ in layout(geometry.size) }
            }
            .frame(height: 220)
            Text(hovered.map { "\(ExplorerFormat.shortTxid($0.txid)) · \(ExplorerFormat.feeRate($0.feeRate)) · \($0.vsize.withCommas) vB" }
                 ?? "\(txs.count.withCommas) transactions. Hover to read one, click to open it.")
                .font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
        }
    }
}

// MARK: - Chain

struct ExplorerChainTab: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var span = 144
    @State private var points: [ExplorerBlockSummary] = []
    @State private var isLoading = false
    @State private var schedule: ExplorerChainSchedule?
    @State private var hashrates: [(height: Int, rate: Double)] = []
    @State private var info: [String: Any] = [:]
    @State private var forks: [[String: Any]]?
    @State private var totals: [String: Any] = [:]
    @State private var peers: [[String: Any]]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    scheduleBox
                    healthBox
                }
                HStack {
                    CypherCaption("Recent blocks")
                    Picker("", selection: $span) {
                        Text("6 hours").tag(36)
                        Text("1 day").tag(144)
                        Text("1 week").tag(1008)
                    }
                    .pickerStyle(.segmented).frame(width: 260)
                    if isLoading { ProgressView().scaleEffect(0.5).frame(width: 18, height: 18) }
                    Spacer()
                }
                if !points.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        chart("Median fee (sat/vB)", points.compactMap { point in point.medianFeeRate.map { (point.height, Double($0)) } })
                        chart("Fullness (%)", points.compactMap { point in point.fullness.map { (point.height, $0 * 100) } })
                        chart("Transactions", points.map { ($0.height, Double($0.txCount)) })
                        chart("Minutes between blocks", intervals)
                    }
                    minersBox
                }
                if !hashrates.isEmpty {
                    chart("Hashrate, daily (\(ExplorerFormat.hashrate(hashrates.last?.rate ?? 0)) now)",
                          hashrates.map { ($0.height, $0.rate / 1e18) })
                }
                peersBox
            }
            .padding(16)
        }
        .task(id: span) { await loadChart() }
        .task(id: model.tip?.hash) { await loadVitals() }
    }

    private var intervals: [(Int, Double)] {
        let sorted = points.sorted { $0.height < $1.height }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, next in
            next.height == previous.height + 1 ? (next.height, max(Double(next.time - previous.time) / 60, 0)) : nil
        }
    }

    private func chart(_ title: String, _ data: [(Int, Double)]) -> some View {
        GroupBox(title) {
            Chart(data, id: \.0) { point in
                LineMark(x: .value("Block", point.0), y: .value(title, point.1))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(Cypher.accent)
            }
            .chartXScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Cypher.line.opacity(0.2))
                    AxisValueLabel { Text((value.as(Int.self) ?? 0).withCommas).font(Cypher.mono(9)).foregroundStyle(Cypher.dim) }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Cypher.line.opacity(0.2))
                    AxisValueLabel { Text(String(format: "%.0f", value.as(Double.self) ?? 0)).font(Cypher.mono(9)).foregroundStyle(Cypher.dim) }
                }
            }
            .frame(height: 130)
        }
    }

    private var minersBox: some View {
        var counts: [String: Int] = [:]
        for point in points { counts[point.miner ?? "Unknown", default: 0] += 1 }
        let ranked = counts.sorted { $0.value > $1.value }
        return GroupBox("Who mined them · from coinbase tags, self-reported") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ranked.prefix(14), id: \.key) { miner, count in
                    ExplorerBar(title: miner, value: String(format: "%d · %.1f%%", count, Double(count) / Double(max(points.count, 1)) * 100),
                                share: Double(count) / Double(max(ranked.first?.value ?? 1, 1)))
                }
                let solo = points.filter(\.isSolo).count
                if solo > 0 {
                    Text("\(solo) solo win\(solo == 1 ? "" : "s") in this window.").font(Cypher.mono(11, weight: .semibold))
                        .foregroundStyle(ExplorerSoloCelebration.gold).padding(.top, 4)
                }
            }
        }
    }

    private var scheduleBox: some View {
        GroupBox("Difficulty and halving") {
            if let schedule = schedule {
                VStack(alignment: .leading, spacing: 8) {
                    if let retarget = schedule.retarget {
                        ProgressView(value: Double(retarget.blocksDone), total: Double(ExplorerChainSchedule.retargetInterval)).tint(Cypher.accent)
                        row("Period", "\(retarget.blocksDone.withCommas) of \(ExplorerChainSchedule.retargetInterval.withCommas) blocks")
                        row("Retarget in", "\(retarget.blocksLeft.withCommas) blocks · \(when(retarget.blocksLeft, schedule.spacing))")
                        if let average = retarget.averageSpacing { row("Block pace", String(format: "%.1f min per block", average / 60)) }
                        row("Projected", retarget.projectedChange.map { String(format: "%@%.2f%% difficulty", $0 >= 0 ? "+" : "", $0) } ?? "Too early in this period")
                    } else {
                        row("Retarget", "Regtest doesn't retarget")
                    }
                    row("Halving at", schedule.halvingHeight.withCommas)
                    row("Halving in", "\(schedule.blocksToHalving.withCommas) blocks · \(when(schedule.blocksToHalving, schedule.spacing))")
                    row("Block reward", "\(subsidy(schedule.subsidyNow)) → \(subsidy(schedule.subsidyAfter)) BTC")
                }
            } else {
                Text("Loading…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            }
        }
    }

    private var healthBox: some View {
        GroupBox("Chain health") {
            VStack(alignment: .leading, spacing: 8) {
                if let tip = model.tip { row("Tip", tip.height.withCommas) }
                if let progress = RPCValue.double(info["verificationprogress"]) {
                    row("Verified", String(format: "%.2f%%", progress * 100) + (model.tip?.inInitialDownload == true ? " · still syncing" : ""))
                }
                if let size = RPCValue.int(info["size_on_disk"]) { row("On disk", ExplorerFormat.size(size)) }
                if let tip = model.tip {
                    row("History", tip.pruneHeight.map { "Pruned below block \($0.withCommas)" } ?? "Every block kept")
                }
                if let forks = forks {
                    let others = forks.filter { RPCValue.string($0["status"]) != "active" }
                    row("Forks seen", others.isEmpty ? "None by this node" : others.count.withCommas)
                    ForEach(Array(others.sorted { (RPCValue.int($0["height"]) ?? 0) > (RPCValue.int($1["height"]) ?? 0) }.prefix(5).enumerated()), id: \.offset) { _, fork in
                        let length = RPCValue.int(fork["branchlen"]) ?? 0
                        row("Block \((RPCValue.int(fork["height"]) ?? 0).withCommas)", "\(length) block\(length == 1 ? "" : "s") · \(RPCValue.string(fork["status"]) ?? "unknown")")
                    }
                }
                if let received = RPCValue.int(totals["totalbytesrecv"]) { row("Downloaded", ExplorerFormat.size(received)) }
                if let sent = RPCValue.int(totals["totalbytessent"]) { row("Uploaded", ExplorerFormat.size(sent)) }
            }
        }
    }

    private var peersBox: some View {
        GroupBox("Peer race · who brought blocks first") {
            if let peers = peers {
                let racers = peers.filter { (RPCValue.int($0["last_block"]) ?? 0) > 0 }.sorted { (RPCValue.int($0["last_block"]) ?? 0) > (RPCValue.int($1["last_block"]) ?? 0) }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(racers.count) of \(peers.count) peers have brought this node a block.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    ForEach(Array(racers.prefix(10).enumerated()), id: \.offset) { _, peer in
                        HStack {
                            Text(RPCValue.string(peer["subver"]) ?? "Unknown client").font(Cypher.mono(11)).foregroundStyle(Cypher.text).lineLimit(1)
                            Text(RPCValue.string(peer["network"]) ?? "").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                            Spacer()
                            Text(ExplorerFormat.ago(RPCValue.int(peer["last_block"]) ?? 0)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                        }
                    }
                }
            } else {
                Text("Loading…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased()).font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.dim).frame(width: 96, alignment: .leading)
            Text(value).font(Cypher.mono(12)).foregroundStyle(Cypher.text)
        }
    }

    private func subsidy(_ value: Double) -> String {
        var text = String(format: "%.8f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text.hasSuffix(".") ? text + "0" : text
    }

    /// "~Mar 2028", or a day and month when it's near.
    private func when(_ blocks: Int, _ spacing: TimeInterval) -> String {
        let date = Date().addingTimeInterval(TimeInterval(blocks) * spacing)
        let format: Date.FormatStyle = blocks < 5000 ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year()
        return "~" + date.formatted(format)
    }

    private func loadChart() async {
        var tip = model.tip
        if tip == nil { tip = try? await model.fetchTip() }
        guard let tip = tip else { return }
        isLoading = true
        // A span change cancels this and starts the next, which is still loading.
        defer { if !Task.isCancelled { isLoading = false } }
        let low = max(tip.height - span + 1, max(tip.pruneHeight ?? 1, 1))
        guard tip.height >= low else { return }
        let heights = Array(low...tip.height)
        points = heights.compactMap { model.summaries[$0] }
        // Newest first, a batch at a time, so a long span fills in as it loads.
        var end = heights.count
        while end > 0, !Task.isCancelled {
            let start = max(end - 24, 0)
            _ = await model.summaries(heights: Array(heights[start..<end]))
            guard !Task.isCancelled else { return }
            points = heights.compactMap { model.summaries[$0] }
            end = start
        }
    }

    private func loadVitals() async {
        var fetched = model.tip
        if fetched == nil { fetched = try? await model.fetchTip() }
        guard let tip = fetched else { return }
        if let response = try? await ExplorerRPC.call("getblockchaininfo") as? [String: Any] { info = response }
        forks = (try? await ExplorerRPC.call("getchaintips")) as? [[String: Any]]
        if let response = try? await ExplorerRPC.call("getnettotals") as? [String: Any] { totals = response }
        peers = (try? await ExplorerRPC.call("getpeerinfo")) as? [[String: Any]]
        let start = tip.height - tip.height % ExplorerChainSchedule.retargetInterval
        var startTime: Int?
        if let hash = try? await model.blockHash(height: start),
           let header = try? await ExplorerRPC.call("getblockheader", ["blockhash": hash]) as? [String: Any] {
            startTime = RPCValue.int(header["time"])
        }
        schedule = ExplorerChainSchedule(height: tip.height, chain: tip.chain, tipTime: tip.time, periodStartTime: startTime)
        // A month of days. Only headers are needed, so it works on a pruned node.
        var rates: [(height: Int, rate: Double)] = []
        for day in (0..<30).reversed() {
            let height = tip.height - day * 144
            guard height > 144 else { continue }
            if let rate = RPCValue.double(try? await ExplorerRPC.call("getnetworkhashps", ["nblocks": 144, "height": height])) {
                rates.append((height, rate))
            }
        }
        hashrates = rates
    }
}

// MARK: - Analyze

struct ExplorerAnalyzeTab: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var text = ""
    @State private var fileError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Analyze a transaction") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paste a raw transaction, a PSBT or a txid. It's read by your own node and nothing is broadcast, so you can check one before it goes anywhere.")
                            .font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                        TextEditor(text: $text)
                            .font(Cypher.mono(11))
                            .frame(height: 150)
                            .padding(4)
                            .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
                        HStack(spacing: 8) {
                            Button("Analyze") { model.search(text) }
                                .buttonStyle(.cypherProminent)
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button {
                                openFile()
                            } label: {
                                Image(systemName: "doc")
                                Text("Open a file…")
                            }
                            Button("Paste") { text = NSPasteboard.general.string(forType: .string) ?? text }
                            Button("Clear") { text = "" }.disabled(text.isEmpty)
                            Spacer()
                        }
                        if let fileError = fileError {
                            Text(fileError).font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
                        }
                    }
                }
                GroupBox("What you get") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(["Where the money goes, and the fee",
                                 "Whether your node would accept it, or what a PSBT still needs",
                                 "A privacy rating with its reasons, and which output is likely change",
                                 "Whether its addresses hold other coins, from your own UTXO set",
                                 "Any data it carries, decoded",
                                 "Where each output was spent, block by block"], id: \.self) { line in
                            Text("· \(line)").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    /// A .psbt file is usually binary; a .txn or text file holds hex or base64.
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), data.count < 10_000_000 else {
            fileError = "Couldn't read that file."
            return
        }
        fileError = nil
        if data.starts(with: Array("psbt".utf8) + [0xFF]) {
            text = data.base64EncodedString()
        } else if let string = String(data: data, encoding: .utf8) {
            text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = Hex.encode(data)
        }
    }
}

// MARK: - Famous

struct ExplorerFamousTab: View {
    @ObservedObject private var model = ExplorerModel.shared
    /// A node scans one at a time, so only one is ever running.
    @State private var scanning: String?
    @State private var progress = 0.0
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var results: [String: ExplorerScanResult] { model.famousResults }
    private var isMainnet: Bool { model.tip?.chain == "main" }
    private var blocks: [ExplorerFamous.Block] {
        ExplorerFamous.blocks.filter { $0.height <= (model.tip?.height ?? 0) && (isMainnet || $0.height == 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Famous coins · checked against your own UTXO set") {
                    if isMainnet {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ExplorerFamous.coins) { coin in coinRow(coin) }
                            if let error = error {
                                Text(error).font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
                            }
                        }
                    } else {
                        Text("These coins are on Bitcoin's main network, and this node is on another.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    }
                }
                GroupBox("Famous blocks") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(blocks) { block in
                            Button {
                                model.show(height: block.height)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(block.height.withCommas).font(Cypher.mono(12, weight: .bold)).foregroundStyle(Cypher.accent).frame(width: 80, alignment: .leading)
                                    Text(block.title).font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                                    Text(block.detail).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                                    Spacer()
                                    if block.height < (model.tip?.pruneHeight ?? 0) { ExplorerTag(text: "PRUNED") }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onDisappear { task?.cancel() }
    }

    private func coinRow(_ coin: ExplorerFamous.Coin) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(coin.title).font(Cypher.mono(12, weight: .bold)).foregroundStyle(Cypher.accent)
                Text(coin.detail).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                if let result = results[coin.title] {
                    Text(result.summary).font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                }
            }
            Spacer()
            if scanning == coin.title {
                ProgressView(value: progress, total: 100).frame(width: 90)
                Button("Stop") {
                    task?.cancel()
                    scanning = nil
                }
            } else if results[coin.title] == nil {
                Button("Check balance") { scan(coin) }.disabled(scanning != nil)
            }
        }
    }

    private func scan(_ coin: ExplorerFamous.Coin) {
        scanning = coin.title
        progress = 0
        error = nil
        task = Task {
            do {
                let result = try await model.scan([coin.descriptor]) { percent in
                    await MainActor.run { progress = percent }
                }
                model.famousResults[coin.title] = result
            } catch let failure as ExplorerError {
                if !Task.isCancelled { error = failure.message }
            } catch {}
            scanning = nil
        }
    }
}

// MARK: - Address

/// An address: its coins now, from the node's UTXO set, and with a block filter index, every block
/// that ever touched it. Nothing about the lookup leaves this Mac.
struct ExplorerAddressView: View {
    let address: String
    @ObservedObject private var model = ExplorerModel.shared
    @State private var result: ExplorerScanResult?
    @State private var progress = 0.0
    @State private var error: String?
    @State private var history: [(height: Int, hash: String)]?
    @State private var historyProgress: Double?
    @State private var historyNote: String?
    @State private var historyTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADDRESS").font(Cypher.mono(16, weight: .bold)).foregroundStyle(Cypher.accent)
                    HStack(spacing: 8) {
                        Text(address).font(Cypher.mono(12)).foregroundStyle(Cypher.text).textSelection(.enabled)
                        Button { explorerCopy(address) } label: { Image(systemName: "doc.on.doc") }.help("Copy")
                    }
                    if let known = ExplorerKnownAddress.note(for: address) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            ExplorerTag(text: known.name)
                            Text(known.detail).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cypherPanel()
                coinsBox
                historyBox
            }
            .padding(16)
        }
        .task { await load() }
        .onDisappear {
            guard historyProgress != nil else { return }
            historyTask?.cancel()
            Task { _ = try? await ExplorerRPC.call("scanblocks", ["action": "abort"]) }
        }
    }

    private var coinsBox: some View {
        GroupBox("Coins now") {
            if let result = result {
                let sorted = result.coins.sorted { $0.amountBtc > $1.amountBtc }
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.summary).font(Cypher.mono(14, weight: .bold)).foregroundStyle(Cypher.text)
                    LazyVStack(spacing: 0) {
                        ForEach(sorted.prefix(500)) { coin in
                            Button {
                                open(coin)
                            } label: {
                                HStack {
                                    Text("\(ExplorerFormat.shortTxid(coin.txid)):\(coin.vout)").font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                                    Spacer()
                                    Text("block \(coin.height.withCommas)").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                                    Text(ExplorerFormat.btc(coin.amountBtc)).font(Cypher.mono(11)).foregroundStyle(Cypher.text).frame(width: 160, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if sorted.count > 500 {
                        Text("Showing the largest 500.").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                    }
                }
            } else if let error = error {
                Text(error).font(Cypher.mono(12)).foregroundStyle(Cypher.amber)
            } else {
                HStack(spacing: 8) {
                    ProgressView(value: progress, total: 100).frame(width: 160)
                    Text("Scanning your UTXO set, about a minute…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    private var historyBox: some View {
        GroupBox("History") {
            if let history = history {
                VStack(alignment: .leading, spacing: 4) {
                    Text(history.isEmpty ? "No block has touched this address." : "\(history.count.withCommas) block\(history.count == 1 ? "" : "s") may have touched it. Filters can rarely match by chance.")
                        .font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                    ForEach(history.prefix(200), id: \.hash) { block in
                        Button("Block \(block.height.withCommas)") { model.show(height: block.height) }
                            .buttonStyle(.plain).font(Cypher.mono(11)).foregroundStyle(Cypher.accent)
                    }
                }
            } else if let progress = historyProgress {
                HStack(spacing: 8) {
                    ProgressView(value: progress, total: 100).frame(width: 160)
                    Text("Checking every block's filter…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
            } else if let note = historyNote {
                Text(note).font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            } else {
                Button("Find every block that touched it") { historyTask = Task { await findHistory() } }
            }
        }
    }

    private func load() async {
        do {
            result = try await model.scan(["addr(\(address))"]) { percent in
                await MainActor.run { progress = percent }
            }
        } catch let failure as ExplorerError {
            if !Task.isCancelled { error = failure.message }
        } catch {
            self.error = Task.isCancelled ? nil : error.localizedDescription
        }
    }

    private func open(_ coin: ExplorerScanResult.Coin) {
        Task {
            let hash = try? await model.blockHash(height: coin.height)
            model.open(.transaction(txid: coin.txid, blockhash: hash, highlightedOutput: coin.vout))
        }
    }

    /// Core's block filters answer this without a full address index, if they're turned on.
    private func findHistory() async {
        historyProgress = 0
        let poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let status = try? await ExplorerRPC.call("scanblocks", ["action": "status"]) as? [String: Any],
                   let percent = RPCValue.double(status["progress"]) {
                    await MainActor.run { historyProgress = percent }
                }
            }
        }
        defer {
            poll.cancel()
            historyProgress = nil
        }
        do {
            guard let response = try await ExplorerRPC.call("scanblocks", ["action": "start", "scanobjects": ["addr(\(address))"]], timeout: 3600) as? [String: Any] else { return }
            let hashes = (response["relevant_blocks"] as? [Any])?.compactMap { $0 as? String } ?? []
            var found: [(height: Int, hash: String)] = []
            for hash in hashes {
                if let header = try? await ExplorerRPC.call("getblockheader", ["blockhash": hash]) as? [String: Any], let height = RPCValue.int(header["height"]) {
                    found.append((height, hash))
                }
            }
            history = found.sorted { $0.height > $1.height }
        } catch let failure as ExplorerError {
            historyNote = failure.message.lowercased().contains("index")
                ? "This needs a block filter index: add blockfilterindex=1 to bitcoin.conf and restart your node. It takes a while to build, and a few GB."
                : failure.message
        } catch {}
    }
}

// MARK: - Your coins

struct ExplorerCoinsView: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var wallets: [String] = []
    @State private var blocks: [ExplorerCoinBlock]?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CypherCaption("Your coins")
                Spacer()
                Picker("Wallet", selection: Binding(get: { model.walletName ?? "" }, set: { choose($0) })) {
                    if model.walletName == nil { Text("Choose a wallet").tag("") }
                    ForEach(wallets, id: \.self) { Text($0.isEmpty ? "Default wallet" : $0).tag($0) }
                }
                .frame(width: 240)
            }
            if wallets.isEmpty {
                Text("No wallet is loaded on your node.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            } else if let error = error {
                Text(error).font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
            } else if let blocks = blocks {
                if blocks.isEmpty {
                    Text("This wallet has no coins yet.").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(blocks) { block in blockRows(block) }
                    }
                }
                .frame(minHeight: 240)
            } else if model.walletName != nil {
                Text("Loading your coins…").font(Cypher.mono(11)).foregroundStyle(Cypher.dim)
            }
        }
        .padding(14)
        .frame(width: 520, height: 420, alignment: .topLeading)
        .background(Cypher.bg)
        .task {
            wallets = await model.loadedWallets()
            if let name = model.walletName, wallets.contains(name) { await load(name) } else if let first = wallets.first, wallets.count == 1 { choose(first) }
        }
    }

    private func blockRows(_ block: ExplorerCoinBlock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                if let height = block.height {
                    model.selectedHeight = height
                } else {
                    model.tab = .mempool
                }
            } label: {
                HStack {
                    Text(block.height.map { "BLOCK \($0.withCommas)" } ?? "UNCONFIRMED").font(Cypher.mono(12, weight: .bold)).foregroundStyle(Cypher.accent)
                    Text("\(block.coins.count) coin\(block.coins.count == 1 ? "" : "s") · \(ExplorerFormat.btc(block.totalBtc))").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                    if let height = block.height, height < (model.tip?.pruneHeight ?? 0) { ExplorerTag(text: "PRUNED") }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(block.coins) { coin in
                Button {
                    Task {
                        let hash: String?
                        if let height = block.height { hash = try? await model.blockHash(height: height) } else { hash = nil }
                        model.open(.transaction(txid: coin.txid, blockhash: hash, highlightedOutput: coin.vout))
                    }
                } label: {
                    HStack {
                        Text("\(ExplorerFormat.shortTxid(coin.txid)):\(coin.vout)").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                        if let label = coin.label { Text(label).font(Cypher.mono(10)).foregroundStyle(Cypher.dim).lineLimit(1) }
                        Spacer()
                        Text(ExplorerFormat.btc(coin.amountBtc)).font(Cypher.mono(11)).foregroundStyle(Cypher.text)
                    }
                    .padding(.leading, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func choose(_ name: String) {
        model.walletName = name
        blocks = nil
        Task {
            await load(name)
            await model.refreshCoins()
        }
    }

    private func load(_ name: String) async {
        error = nil
        do {
            blocks = try await model.walletCoins(wallet: name)
        } catch let failure as ExplorerError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
