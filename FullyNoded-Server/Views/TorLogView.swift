//
//  TorLogView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/22/25.
//

import SwiftUI

struct TorLogView: View {
    @StateObject private var monitor: TorLogMonitor
    
    init() {
        _monitor = StateObject(wrappedValue: TorLogMonitor())
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(color(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            //.padding()
        }
        .background(Color.black)
        .scrollTargetBehavior(.paging)
        .defaultScrollAnchor(.bottom)
        .onChange(of: monitor.lines) { }
    }
    
    private func color(for line: String) -> Color {
        if line.contains("Warn") { return .orange }
        if line.contains("Err") { return .red }
        if line.contains("Bootstrapped 100%") { return .green }
        return .gray
    }
}
