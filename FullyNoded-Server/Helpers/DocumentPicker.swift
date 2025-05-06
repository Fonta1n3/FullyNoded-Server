//
//  DocumentPicker.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 5/5/25.
//

import SwiftUI

// SwiftUI wrapper for NSOpenPanel
struct FilePicker: NSViewControllerRepresentable {
    var completion: (String?) -> Void
    var defaultPath: String // New parameter for default directory path
    
    func makeNSViewController(context: Context) -> NSViewController {
        let controller = NSViewController()
        context.coordinator.controller = controller
        
        // Present the open panel asynchronously to avoid transaction conflicts
        DispatchQueue.main.async {
            context.coordinator.showOpenPanel(defaultPath: self.defaultPath)
        }
        
        return controller
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // No updates needed, as the panel is shown once on creation
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject {
        var completion: (String?) -> Void
        weak var controller: NSViewController?
        
        init(completion: @escaping (String?) -> Void) {
            self.completion = completion
        }
        
        func showOpenPanel(defaultPath: String) {
            let openPanel = NSOpenPanel()
            openPanel.title = "Select a Wallet Directory"
            openPanel.showsResizeIndicator = true
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = true // Allow directory selection
            openPanel.canChooseFiles = false // Disallow file selection
            openPanel.allowsMultipleSelection = false
            // Set default directory path
            openPanel.directoryURL = URL(fileURLWithPath: defaultPath)
            
            // Use sheet if a window is available, otherwise run modally
            if let window = controller?.view.window {
                openPanel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = openPanel.url {
                        self.completion(url.path)
                    } else {
                        self.completion(nil)
                    }
                }
            } else {
                let response = openPanel.runModal()
                if response == .OK, let url = openPanel.url {
                    self.completion(url.path)
                } else {
                    self.completion(nil)
                }
            }
        }
    }
}
