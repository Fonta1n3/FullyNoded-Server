//
//  DropDownAlert.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/31/25.
//

import SwiftUI

// MARK: - Reusable Dropdown Alert (Sheet Style)
struct MineBlocksSheet: View {
    @Binding var isPresented: Bool
    
    @Binding var selectedWallet: String
    @Binding var selectedBlocks: String
    
    let wallets: [String]           // e.g. ["Regtest Wallet #1", "Hot Wallet"]
    let blockOptions: [String]      // e.g. ["1", "10", "50", "100", "500", "1000"]
    
    let onConfirm: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet") {
                    Picker("Select wallet", selection: $selectedWallet) {
                        ForEach(wallets, id: \.self) { wallet in
                            Text(wallet).tag(wallet)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Number of blocks to mine") {
                    Picker("Blocks", selection: $selectedBlocks) {
                        ForEach(blockOptions, id: \.self) { blocks in
                            Text("\(blocks) block\(blocks == "1" ? "" : "s")").tag(blocks)
                        }
                    }
                    .pickerStyle(.menu)  // Nice scrolling wheel on iPhone
                }
            }
            .navigationTitle("Mine Blocks")
            //.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mine") {
                        onConfirm()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
