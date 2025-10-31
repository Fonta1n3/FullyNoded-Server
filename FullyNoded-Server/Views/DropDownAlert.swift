//
//  DropDownAlert.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/31/25.
//

import SwiftUI

// MARK: - Reusable Dropdown Alert (Sheet Style)
struct DropdownAlert: View {
    @Binding var isPresented: Bool
    @Binding var selection: String
    let title: String
    let options: [String]
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top)
            
            // Dropdown (Picker)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.horizontal)
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("OK") {
                    onConfirm()
                    isPresented = false
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(maxWidth: 300)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .padding()
    }
}
