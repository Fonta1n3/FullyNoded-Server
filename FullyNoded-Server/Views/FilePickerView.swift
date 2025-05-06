//
//  FilePickerView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 5/5/25.
//

import SwiftUI

// Reusable FilePickerView
struct FilePickerView: View {
    @Binding var selectedPath: String? // Binding to store the selected directory path
    let buttonLabel: String // Customizable button label
    let defaultPath: String // New parameter for default directory path
    let onDirectorySelected: (String) -> Void // Callback for when a directory is selected
    @State private var isShowingPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Selected Directory Path:")
                .font(.headline)
            
            Text(selectedPath ?? "No directory selected")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding()
            
            Button(action: {
                isShowingPicker = true
            }) {
                Text(buttonLabel)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            FilePicker(completion: { path in
                selectedPath = path
                if let path = path {
                    onDirectorySelected(path) // Call the callback with the selected path
                }
                isShowingPicker = false // Dismiss the sheet
            }, defaultPath: defaultPath)
        }
    }
}
