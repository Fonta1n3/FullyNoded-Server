//
//  BitcoinKnots.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/24/25.
//

import SwiftUI

/// The Bitcoin Knots page (see NodeView).
struct BitcoinKnots: View {
    var body: some View {
        NodeView(monitor: .knots)
    }
}

#Preview {
    BitcoinKnots()
}
