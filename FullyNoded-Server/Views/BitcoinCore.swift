//
//  BitcoinCore.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

/// The Bitcoin Core page (see NodeView).
struct BitcoinCore: View {
    var body: some View {
        NodeView(monitor: .core)
    }
}
