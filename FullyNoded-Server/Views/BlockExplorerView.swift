//
//  BlockExplorerView.swift
//  FullyNoded-Server
//
//  The block explorer's page: one search box for anything, the tabs, and the strip of blocks with
//  the next one being mined. Everything comes from this Mac's own node, nothing from a website.
//
//  The mining animation is decoration: nobody can see anyone's hashing. The tiles it draws are
//  real though, the transactions of the block this node would build right now.
//

import SwiftUI
import AVFoundation

/// Fee rates as colours, cool to hot, in the buckets the legend shows.
enum ExplorerFeeColor {
    static let buckets: [(from: Double, label: String, color: Color)] = [
        (0, "<2", Color(red: 0.16, green: 0.45, blue: 0.50)),
        (2, "2", Color(red: 0.13, green: 0.68, blue: 0.62)),
        (5, "5", Color(red: 0.25, green: 0.85, blue: 0.48)),
        (10, "10", Color(red: 0.72, green: 0.88, blue: 0.27)),
        (25, "25", Color(red: 1.0, green: 0.72, blue: 0.28)),
        (50, "50", Color(red: 1.0, green: 0.45, blue: 0.32)),
        (100, "100+", Color(red: 1.0, green: 0.28, blue: 0.48))
    ]

    static func color(_ feeRate: Double?) -> Color {
        guard let feeRate = feeRate else { return Color(white: 0.4) }
        return buckets.last { feeRate >= $0.from }?.color ?? buckets[0].color
    }
}

struct BlockExplorerView: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var query = ""
    @State private var newBlockFrame: CGRect?
    @State private var burst: (id: Int, origin: CGPoint)?
    @AppStorage(ExplorerChime.key) private var chimeOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A block was found: confetti from where it lands in the strip, and a chime. Not while the
    /// node's catching up, when that would be every few seconds.
    private func celebrate() {
        guard model.tip?.inInitialDownload != true else { return }
        if chimeOn { ExplorerChime.play() }
        guard !reduceMotion else { return }
        // As the block lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // On another tab there's no block to come out of, so from the top.
            let origin = newBlockFrame.map { CGPoint(x: $0.midX, y: $0.minY + 30) } ?? CGPoint(x: 320, y: 60)
            burst = ((burst?.id ?? 0) + 1, origin)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let route = model.path.last {
                backBar
                routeView(route).id(route)
            } else {
                tabBar
                content
            }
        }
        .overlay {
            if let burst = burst {
                ExplorerConfetti(origin: burst.origin).id(burst.id)
                    .task(id: burst.id) {
                        try? await Task.sleep(nanoseconds: UInt64(ExplorerConfetti.duration * 1e9))
                        if self.burst?.id == burst.id { self.burst = nil }
                    }
            }
        }
        .overlay { if let win = model.soloWin { ExplorerSoloCelebration(win: win) { model.soloWin = nil } } }
        .coordinateSpace(name: ExplorerNewBlockFrame.space)
        .onPreferenceChange(ExplorerNewBlockFrame.self) { newBlockFrame = $0 }
        .onChange(of: model.justMined) { _, height in if height != nil { celebrate() } }
        .onChange(of: model.tab) { _, _ in model.searchError = nil }
        .onAppear { model.startWatching() }
        .onDisappear { model.stopWatching() }
    }

    // MARK: - Search

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image("logo").resizable().scaledToFit().frame(width: 18, height: 18)
                    Text("FULLY NODED").font(Cypher.mono(10, weight: .bold)).foregroundStyle(Cypher.dim).kerning(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Cypher.dim)
                    TextField("Height, block hash, txid, address, raw transaction or PSBT", text: $query)
                        .textFieldStyle(.plain)
                        .font(Cypher.mono(12))
                        .onSubmit { model.search(query) }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Cypher.panel)
                .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
                if model.isSearching {
                    if let progress = model.searchProgress {
                        Text("Looking through your node's blocks: \(progress.done.withCommas) of \(progress.total.withCommas)")
                            .font(Cypher.mono(11)).foregroundStyle(Cypher.dim).fixedSize()
                    } else {
                        ProgressView().scaleEffect(0.5).frame(width: 18, height: 18)
                    }
                    Button("Stop") { model.cancelSearch() }
                } else {
                    Button("Go") { model.search(query) }.disabled(query.isEmpty)
                }
            }
            if let error = model.searchError {
                Text(error).font(Cypher.mono(11)).foregroundStyle(Cypher.amber)
            }
            if let error = model.connectionError {
                Text("Can't reach your node: \(error)").font(Cypher.mono(11)).foregroundStyle(Cypher.danger)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var backBar: some View {
        HStack {
            Button {
                _ = model.path.popLast()
            } label: {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            if model.path.count > 1 {
                Button("Close all") { model.path = [] }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ExplorerTab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                        Text(tab.rawValue)
                    }
                    .font(Cypher.mono(12, weight: .semibold))
                    .foregroundStyle(model.tab == tab ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(Cypher.dim))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(model.tab == tab ? AnyShapeStyle(Cypher.accent) : AnyShapeStyle(Color.clear)).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let tip = model.tip {
                Text("\(NodeMonitor.networkName(tip.chain).uppercased()) · TIP \(tip.height.withCommas)\(tip.isPruned ? " · PRUNED" : "")")
                    .font(Cypher.mono(10, weight: .bold)).foregroundStyle(Cypher.dim)
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Cypher.line).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .blocks: ExplorerBlocksTab()
        case .mempool: ExplorerMempoolTab()
        case .chain: ExplorerChainTab()
        case .analyze: ExplorerAnalyzeTab()
        case .famous: ExplorerFamousTab()
        }
    }

    @ViewBuilder private func routeView(_ route: ExplorerRoute) -> some View {
        switch route {
        case .transaction(let txid, let blockhash, let highlighted):
            ExplorerTransactionView(source: .txid(txid, blockhash: blockhash), highlightedOutput: highlighted)
        case .analysis(let input):
            ExplorerTransactionView(source: .pasted(input), highlightedOutput: nil)
        case .address(let address):
            ExplorerAddressView(address: address)
        }
    }
}

// MARK: - Blocks tab

struct ExplorerBlocksTab: View {
    @ObservedObject private var model = ExplorerModel.shared
    @State private var showingCoins = false
    @AppStorage(ExplorerChime.key) private var chimeOn = true

    var body: some View {
        VStack(spacing: 0) {
            if let tip = model.tip {
                ExplorerStrip(tip: tip)
                HStack(spacing: 8) {
                    if model.selectedHeight != tip.height {
                        Button("Latest block") { model.selectedHeight = tip.height }
                    }
                    Spacer()
                    Button {
                        chimeOn.toggle()
                        if chimeOn { ExplorerChime.play() }
                    } label: {
                        Image(systemName: chimeOn ? "speaker.wave.2" : "speaker.slash")
                    }
                    .help(chimeOn ? "Turn off the sound for a new block" : "Play a sound for a new block")
                    Button {
                        showingCoins = true
                    } label: {
                        Image(systemName: "bitcoinsign.circle")
                        Text("Your coins")
                    }
                    .popover(isPresented: $showingCoins) { ExplorerCoinsView().environment(\.cypherPalette, .explorer) }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                Rectangle().fill(Cypher.line).frame(height: 1)
                if let height = model.selectedHeight {
                    ExplorerBlockDetailView(height: height).id(height)
                } else {
                    Spacer()
                }
            } else {
                Spacer()
                Text(model.connectionError == nil ? "Connecting to your node…" : "Start your node to explore its chain.")
                    .font(Cypher.mono(13)).foregroundStyle(Cypher.dim)
                Spacer()
            }
        }
    }
}

/// Blocks in chain order, oldest on the left, ending with the tip and then the next block on the
/// right. Only a window of the chain is laid out, and it follows wherever the selection goes, so
/// jumping to block 170 works like anywhere else. A button on its left edge brings in older ones:
/// doing that on reaching the edge would keep finding itself still at the edge, all the way to genesis.
private struct ExplorerStrip: View {
    let tip: ExplorerTip
    @ObservedObject private var model = ExplorerModel.shared
    @State private var low: Int?
    @State private var top: Int?

    private static let page = 150

    private var heights: [Int] {
        let top = min(self.top ?? tip.height, tip.height)
        let low = max(self.low ?? top - Self.page, 0)
        return top >= low ? Array(low...top) : []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 14) {
                    if let oldest = heights.first, oldest > 0 {
                        Button {
                            loadOlder(from: oldest, proxy)
                        } label: {
                            Image(systemName: "chevron.left.2")
                            Text("Older")
                        }
                    }
                    ForEach(heights, id: \.self) { height in
                        ExplorerCube(height: height, isSelected: model.selectedHeight == height, isNew: model.justMined == height,
                                     hasCoins: model.coinHeights.contains(height),
                                     isPruned: height < (tip.pruneHeight ?? 0))
                            .id(height)
                            .onAppear { model.requestSummary(height) }
                            .onTapGesture { model.selectedHeight = height }
                    }
                    if (top ?? tip.height) >= tip.height {
                        ExplorerNextBlockCube(tip: tip).id("next")
                    } else {
                        Button {
                            top = nil
                            low = nil
                            model.selectedHeight = tip.height
                        } label: {
                            Text("Tip")
                            Image(systemName: "chevron.right.2")
                        }
                        .id("next")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .defaultScrollAnchor(.trailing)
            .frame(height: 216)
            .onChange(of: model.selectedHeight) { _, height in
                guard let height = height else { return }
                if height == tip.height {
                    top = nil
                    low = nil
                } else if !heights.contains(height) {
                    top = min(height + 20, tip.height)
                    low = max(height - Self.page, 0)
                }
                DispatchQueue.main.async {
                    withAnimation {
                        // The tip, with the next block beside it.
                        if height == tip.height {
                            proxy.scrollTo("next", anchor: .trailing)
                        } else {
                            proxy.scrollTo(height, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// Adding on the left would push what's on screen along, so it's put back where it was.
    private func loadOlder(from height: Int, _ proxy: ScrollViewProxy) {
        low = max(height - Self.page, 0)
        // Once the new blocks are laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo(height, anchor: .leading) }
    }
}

/// A block as a cube, its front filled by how full it is and coloured by what it paid.
private struct ExplorerCube: View {
    let height: Int
    let isSelected: Bool
    let isNew: Bool
    let hasCoins: Bool
    let isPruned: Bool
    @ObservedObject private var model = ExplorerModel.shared
    @Environment(\.cypherPalette) private var palette

    nonisolated private static let side: CGFloat = 158

    var body: some View {
        let summary = model.summaries[height]
        let fill = ExplorerFeeColor.color(summary?.medianFeeRate.map(Double.init))
        // The animation's closures can't read the view's state.
        let accent = palette.accent, still = reduceMotion
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let depth: CGFloat = 12
                let front = CGRect(x: 0, y: depth, width: size.width - depth, height: size.height - depth)
                var top = Path()
                top.move(to: CGPoint(x: 0, y: depth))
                top.addLine(to: CGPoint(x: depth, y: 0))
                top.addLine(to: CGPoint(x: size.width, y: 0))
                top.addLine(to: CGPoint(x: size.width - depth, y: depth))
                top.closeSubpath()
                context.fill(top, with: .color(palette.accent.opacity(0.28)))
                var sidePath = Path()
                sidePath.move(to: CGPoint(x: size.width - depth, y: depth))
                sidePath.addLine(to: CGPoint(x: size.width, y: 0))
                sidePath.addLine(to: CGPoint(x: size.width, y: size.height - depth))
                sidePath.addLine(to: CGPoint(x: size.width - depth, y: size.height))
                sidePath.closeSubpath()
                context.fill(sidePath, with: .color(palette.accent.opacity(0.14)))
                context.fill(Path(front), with: .color(palette.panel))
                let fullness = CGFloat(summary?.fullness ?? 0)
                let fillRect = CGRect(x: front.minX, y: front.maxY - front.height * fullness, width: front.width, height: front.height * fullness)
                context.fill(Path(fillRect), with: .color(fill.opacity(0.32)))
                context.stroke(Path(front), with: .color(isSelected ? palette.accent : palette.line), lineWidth: isSelected ? 2 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(height.withCommas)
                    .font(Cypher.mono(14, weight: .bold))
                    .foregroundStyle(Cypher.accent)
                if let summary = summary {
                    Text(summary.isSolo ? "SOLO WIN" : (summary.miner ?? (isPruned ? "" : "Unknown miner")))
                        .font(Cypher.mono(10, weight: .bold))
                        .foregroundStyle(summary.isSolo ? AnyShapeStyle(ExplorerSoloCelebration.gold) : AnyShapeStyle(Cypher.text))
                        .lineLimit(1)
                    Text(ExplorerFormat.ago(summary.time)).font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                    Spacer(minLength: 2)
                    if let rate = summary.medianFeeRate {
                        Text("~\(rate) sat/vB").font(Cypher.mono(12, weight: .semibold)).foregroundStyle(Cypher.text)
                    }
                    Text("\(summary.txCount.withCommas) txs").font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                    if let reward = summary.rewardBtc {
                        Text(ExplorerFormat.btcShort(reward)).font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                    }
                    if let size = summary.size, let weight = summary.weight {
                        Text(String(format: "%.2f MB · %.2f MWU", Double(size) / 1e6, Double(weight) / 1e6))
                            .font(Cypher.mono(9)).foregroundStyle(Cypher.dim)
                    } else if isPruned {
                        Text("PRUNED").font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.dim)
                    }
                } else {
                    Spacer()
                    Text("loading…").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                }
                if hasCoins {
                    Text("YOUR COINS").font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.bg)
                        .padding(.horizontal, 4).background(Cypher.accent)
                }
            }
            .padding(.leading, 9).padding(.trailing, 20).padding(.top, 19).padding(.bottom, 7)
        }
        .frame(width: Self.side, height: Self.side + 20)
        .keyframeAnimator(initialValue: Landing(), trigger: landings) { cube, value in
            cube
                .overlay(alignment: .bottomLeading) { Self.glowFrame(value, accent: accent, still: still) }
                .overlay(alignment: .top) {
                    Label("CONFIRMED", systemImage: "checkmark")
                        .font(Cypher.mono(9, weight: .bold)).foregroundStyle(Cypher.bg)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(accent)
                        .offset(y: -9)
                        .opacity(value.glow)
                }
                .shadow(color: accent.opacity(0.7 * value.glow), radius: 14 * value.glow)
                .scaleEffect(still ? 1 : value.scale, anchor: .bottom)
                .offset(y: still ? 0 : value.drop)
                .opacity(still ? 1 : value.opacity)
        } keyframes: { _ in
            // Drops into the chain where the next block was, bounces, and glows for a moment.
            KeyframeTrack(\.drop) {
                MoveKeyframe(-44)
                SpringKeyframe(0, duration: 0.6, spring: Spring(response: 0.45, dampingRatio: 0.55))
            }
            KeyframeTrack(\.scale) {
                MoveKeyframe(0.88)
                SpringKeyframe(1, duration: 0.8, spring: .bouncy)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.2)
            }
            KeyframeTrack(\.glow) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 1.8)
                CubicKeyframe(0, duration: 0.8)
            }
            KeyframeTrack(\.ring) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.35)
                CubicKeyframe(1, duration: 0.9)
            }
        }
        .background {
            if isNew {
                GeometryReader { geometry in
                    Color.clear.preference(key: ExplorerNewBlockFrame.self, value: geometry.frame(in: .named(ExplorerNewBlockFrame.space)))
                }
            }
        }
        .onAppear { if isNew { landings += 1 } }
        .onChange(of: isNew) { _, isNew in if isNew { landings += 1 } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The front face lit up, and a ring going out from it as the block lands.
    nonisolated private static func glowFrame(_ value: Landing, accent: Color, still: Bool) -> some View {
        let face = Rectangle().frame(width: side - 12, height: side + 8)
        return ZStack {
            face.foregroundStyle(.clear).overlay(Rectangle().stroke(accent, lineWidth: 2)).opacity(value.glow)
            if !still, value.ring > 0, value.ring < 1 {
                face.foregroundStyle(.clear).overlay(Rectangle().stroke(accent, lineWidth: 2 * (1 - value.ring) + 0.5))
                    .scaleEffect(1 + 0.22 * value.ring)
                    .opacity(0.9 * (1 - value.ring))
            }
        }
        .allowsHitTesting(false)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landings = 0

    private struct Landing {
        var drop: CGFloat = 0
        var scale: CGFloat = 1
        var opacity: Double = 1
        var glow: Double = 0
        var ring: CGFloat = 0
    }
}

/// The block this node would build right now, its real transactions as tiles, with a beam going
/// over them while it's "mined".
private struct ExplorerNextBlockCube: View {
    let tip: ExplorerTip
    @ObservedObject private var model = ExplorerModel.shared
    @Environment(\.cypherPalette) private var palette
    @State private var tiles: [(rect: CGRect, color: Color)] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blocksFound = 0

    private struct Refill {
        var flash: Double = 0
        var slide: CGFloat = 0
        var opacity: Double = 1
    }

    private static let size = CGSize(width: 150, height: 166)

    var body: some View {
        // The animation's closures can't read the view's state.
        let accent = palette.accent, still = reduceMotion
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    for tile in tiles where tile.rect.width > 0.5 && tile.rect.height > 0.5 {
                        context.fill(Path(tile.rect.insetBy(dx: 0.3, dy: 0.3)), with: .color(tile.color.opacity(0.42)))
                    }
                    // A soft beam, back and forth.
                    let beam = (sin(time * 1.1) + 1) / 2 * size.width
                    let rect = CGRect(x: beam - 28, y: 0, width: 56, height: size.height)
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [.clear, palette.accent.opacity(0.30), .clear]),
                        startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
                    var outline = StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    outline.dashPhase = CGFloat(-time * 14)
                    context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(palette.accent), style: outline)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT BLOCK").font(Cypher.mono(12, weight: .bold)).foregroundStyle(Cypher.accent)
                    if let time = model.summaries[tip.height]?.time ?? tip.time {
                        Text(ExplorerFormat.eta(lastBlockTime: time)).font(Cypher.mono(16, weight: .bold)).foregroundStyle(Cypher.text)
                    }
                }
                .padding(4)
                .background(Cypher.bg.opacity(0.78))
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    if !model.template.isEmpty {
                        Text("\(model.template.count.withCommas) txs ready").font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                        Text(ExplorerFormat.btc(sats: model.template.reduce(0) { $0 + $1.feeSats }).replacingOccurrences(of: " BTC", with: "") + " fees")
                            .font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                    }
                    if let size = RPCValue.int(model.mempoolInfo["size"]) {
                        Text("\(size.withCommas) in mempool").font(Cypher.mono(10)).foregroundStyle(Cypher.text)
                    }
                }
                .padding(4)
                // Readable over the tiles.
                .background(Cypher.bg.opacity(0.78))
            }
            .padding(6)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .keyframeAnimator(initialValue: Refill(), trigger: blocksFound) { cube, value in
            cube
                .overlay { Rectangle().fill(accent.opacity(0.45 * value.flash)).allowsHitTesting(false) }
                .offset(x: still ? 0 : value.slide)
                .opacity(still ? 1 : value.opacity)
        } keyframes: { _ in
            // Its block was just found: it flashes, then a new one comes in behind it.
            KeyframeTrack(\.flash) {
                MoveKeyframe(1)
                CubicKeyframe(0, duration: 0.7)
            }
            KeyframeTrack(\.slide) {
                MoveKeyframe(48)
                SpringKeyframe(0, duration: 0.7, spring: .smooth)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0.2)
                LinearKeyframe(1, duration: 0.5)
            }
        }
        .onChange(of: model.justMined) { _, height in if height != nil { blocksFound += 1 } }
        .contentShape(Rectangle())
        .onTapGesture { model.tab = .mempool }
        .help("A guide only: blocks are found at random. The tiles are the transactions your node would mine right now.")
        .onAppear(perform: layoutTiles)
        .onChange(of: model.templateRevision) { _, _ in layoutTiles() }
    }

    private func layoutTiles() {
        // More than this can't be seen at this size.
        let txs = model.template.sorted { $0.vsize > $1.vsize }.prefix(500)
        let total = Double(txs.reduce(0) { $0 + $1.vsize })
        // A partly full template leaves part of the cube empty.
        let filled = max(min(total / Double(MempoolDigest.blockVSize), 1), 0.02)
        let height = Self.size.height * filled.squareRoot()
        let width = Self.size.width * filled.squareRoot()
        let rects = ExplorerTreemap.layout(areas: txs.map { Double($0.vsize) }, in: CGSize(width: width, height: height))
        tiles = zip(rects, txs).map { rect, tx in
            (rect.offsetBy(dx: Self.size.width - width, dy: Self.size.height - height), ExplorerFeeColor.color(tx.feeRate))
        }
    }
}

// MARK: - Solo celebration

/// A little party for a solo miner's win: one small miner beating the whole network. Self-reported
/// like any coinbase tag.
struct ExplorerSoloCelebration: View {
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.30)
    let win: ExplorerSoloWin
    let onClose: () -> Void
    @State private var start = Date()

    private static let coins: [(x: Double, speed: Double, size: Double, phase: Double)] = (0..<60).map { index in
        let seed = Double(index)
        return (x: (seed * 0.6180339).truncatingRemainder(dividingBy: 1), speed: 0.10 + (seed * 0.37).truncatingRemainder(dividingBy: 0.16),
                size: 12 + (seed * 3.3).truncatingRemainder(dividingBy: 14), phase: (seed * 0.77).truncatingRemainder(dividingBy: 1))
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    for coin in Self.coins {
                        let y = (coin.phase + elapsed * coin.speed).truncatingRemainder(dividingBy: 1.1) - 0.05
                        let point = CGPoint(x: coin.x * size.width + sin(elapsed + coin.phase * 6) * 12, y: y * size.height)
                        context.draw(Text("₿").font(.system(size: coin.size, weight: .bold, design: .rounded)).foregroundStyle(Self.gold.opacity(0.85)), at: point)
                    }
                }
            }
            .allowsHitTesting(false)
            VStack(spacing: 8) {
                Text("SOLO BLOCK").font(Cypher.mono(26, weight: .bold)).foregroundStyle(Self.gold)
                Text("Block \(win.height.withCommas)" + (win.miner.map { " · \($0)" } ?? ""))
                    .font(Cypher.mono(13, weight: .semibold)).foregroundStyle(Cypher.text)
                if let reward = win.rewardBtc {
                    Text("One small miner just won \(ExplorerFormat.btc(reward))").font(Cypher.mono(12)).foregroundStyle(Cypher.text)
                }
                Text("As the block's own coinbase says").font(Cypher.mono(10)).foregroundStyle(Cypher.dim)
                Button("Nice", action: onClose).buttonStyle(.cypherProminent).padding(.top, 4)
            }
            .padding(24)
            .background(Cypher.panel)
            .overlay(Rectangle().stroke(Self.gold, lineWidth: 1))
        }
        .task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            onClose()
        }
    }
}

// MARK: - New block

/// Where the new block is in the strip, for the confetti to come out of.
struct ExplorerNewBlockFrame: PreferenceKey {
    static let space = "explorer"
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

/// A burst of confetti in the fee colours, thrown up and falling back down.
struct ExplorerConfetti: View {
    static let duration = 3.2
    let origin: CGPoint
    @State private var start = Date()

    private struct Piece {
        let angle, speed, spin, wobble, size: Double
        let color: Color
        let isRound: Bool
    }

    private static let pieces: [Piece] = {
        let colors = ExplorerFeeColor.buckets.map(\.color) + [ExplorerSoloCelebration.gold, .white]
        var rng = SystemRandomNumberGenerator()
        return (0..<140).map { _ in
            Piece(angle: -Double.pi / 2 + .random(in: -1.15...1.15, using: &rng), speed: .random(in: 320...820, using: &rng),
                  spin: .random(in: -9...9, using: &rng), wobble: .random(in: 0...(2 * .pi), using: &rng),
                  size: .random(in: 5...10, using: &rng), color: colors.randomElement(using: &rng) ?? .white,
                  isRound: .random(using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = timeline.date.timeIntervalSince(start)
                // Air slows them; gravity brings them down to flutter.
                let drag = 2.2, gravity = 620.0
                let slowed = (1 - exp(-drag * t)) / drag
                let fade = max(0, min(1, (Self.duration - t) / 0.9))
                for piece in Self.pieces {
                    let x = origin.x + cos(piece.angle) * piece.speed * slowed + sin(t * 5 + piece.wobble) * 10
                    let y = origin.y + sin(piece.angle) * piece.speed * slowed + gravity * (t - slowed) / drag
                    var copy = context
                    copy.opacity = fade
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * t + piece.wobble))
                    // Turning over, so it catches the light now and then.
                    let flip = abs(cos(t * piece.spin * 0.7 + piece.wobble))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size * 0.3 * flip, width: piece.size, height: piece.size * 0.6 * max(flip, 0.15))
                    copy.fill(piece.isRound ? Path(ellipseIn: rect) : Path(rect), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A short rising chime for a new block, made here rather than shipped as a sound file.
@MainActor
enum ExplorerChime {
    static let key = "explorerBlockChime"
    private static var player: AVAudioPlayer?

    static func play() {
        if player == nil { player = try? AVAudioPlayer(data: wav()) }
        player?.volume = 0.55
        player?.currentTime = 0
        player?.play()
    }

    /// Three bell-like notes, G5 C6 E6, each fading out, as 16-bit mono WAV.
    private static func wav() -> Data {
        let rate = 44_100.0, length = 1.3
        let notes: [(start: Double, frequency: Double)] = [(0, 783.99), (0.09, 1046.5), (0.18, 1318.5)]
        let samples = (0..<Int(rate * length)).map { index -> Int16 in
            let t = Double(index) / rate
            var value = 0.0
            for note in notes where t >= note.start {
                let local = t - note.start
                let envelope = min(local / 0.004, 1) * exp(-local * 4.2)
                // A little of the octave above makes it ring.
                value += envelope * (sin(2 * .pi * note.frequency * local) + 0.3 * sin(4 * .pi * note.frequency * local))
            }
            return Int16(max(-1, min(1, value * 0.3)) * Double(Int16.max))
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        samples.forEach { append($0) }
        return data
    }
}
