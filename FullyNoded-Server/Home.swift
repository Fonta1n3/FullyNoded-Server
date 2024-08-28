//
//  Home.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 8/28/24.
//

import SwiftUI

struct Home: View {
    var body: some View {
        Image("1024")
            .resizable()
            .cornerRadius(20.0)
            .frame(width: 300.0, height: 300.0)
            .padding([.all])
    }
}

#Preview {
    Home()
}
