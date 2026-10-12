//
//  JMSessionView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 5/12/25.
//

import SwiftUI

struct StatusView: View {
    let isActive: Bool
    let statusText: String
    let statusImage: String
    
    var body: some View {
        HStack {
            Image(systemName: statusImage)
                .foregroundStyle(isActive ? Cypher.accent : Cypher.danger)
            Text(statusText)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}
