//
//  TorLogView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/22/25.
//

import SwiftUI

struct TorLogView: View {
    @StateObject private var monitor = TorLogMonitor()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(monitor.lines) { line in
                        Text(line.text)
                            .font(Cypher.mono(10.5))
                            .foregroundStyle(Self.color(for: line.text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .textSelection(.enabled)
            .defaultScrollAnchor(.bottom)
            .onChange(of: monitor.lines) {
                if let last = monitor.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .overlay {
                if monitor.lines.isEmpty {
                    Text("No tor log yet.")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                }
            }
        }
    }

    /// tor's levels are lowercase in brackets: "Oct 22 10:00:00.000 [warn] …".
    static func color(for line: String) -> Color {
        if line.contains("[err]") { return Cypher.danger }
        if line.contains("[warn]") { return Cypher.amber }
        if line.contains("Bootstrapped 100%") { return Cypher.accent }
        return Cypher.dim
    }
}
