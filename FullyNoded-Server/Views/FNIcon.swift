//
//  FNIcon.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/13/24.
//

import SwiftUI

struct FNIcon: View {
    var body: some View {
        Image("1024")
            .resizable()
            .cornerRadius(20.0)
            .frame(width: 80.0, height: 80.0)
            .padding([.all])
            .scaledToFit()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        //Spacer()
    }
}

#Preview {
    FNIcon()
}
