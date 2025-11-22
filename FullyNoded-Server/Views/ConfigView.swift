//
//  ConfigView.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/22/25.
//

import SwiftUI

struct ConfigTextView: View {
    let configString: String
    let title: String
    let contentType: ConfigContentType
    
    enum ConfigContentType {
        case json, yaml, plist, toml, ini, plain
        
        var language: String {
            switch self {
            case .json:  return "json"
            case .yaml:  return "yaml"
            case .plist: return "xml"      // plist is XML-based
            case .toml:  return "toml"
            case .ini:   return "ini"
            case .plain: return "plaintext"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    Pasteboard.write(configString)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            
            ScrollView([.horizontal, .vertical]) {
                Text(configString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .backgroundStyle(.background)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(white: 0.8), lineWidth: 1)
                    )
                    // Optional: Syntax highlighting using a simple approach
                    // For full syntax highlighting, consider integrating Highlightr or similar
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 400)
            .padding()
        }
        .padding()
        .backgroundStyle(.background)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Preview & Example Usage

#Preview {
    ConfigTextView(
        configString: """
        {
            "appName": "MyAwesomeApp",
            "version": "2.1.0",
            "features": {
                "darkMode": true,
                "analytics": false,
                "notifications": true
            },
            "api": {
                "baseURL": "https://api.example.com",
                "timeout": 30
            }
        }
        """,
        title: "config.json",
        contentType: .json
    )
    .frame(width: 600, height: 500)
    .padding()
}

