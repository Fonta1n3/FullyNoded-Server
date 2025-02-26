//
//  BlockchainInfoView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 2/25/25.
//

import SwiftUI

struct BlockchainInfoView: View {
    
    let blockchainInfo: BlockchainInfo
    
    var body: some View {
        Text(blockchainInfo.text)
    }
}

