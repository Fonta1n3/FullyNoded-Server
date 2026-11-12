//
//  CypherTheme.swift
//  FullyNoded-Server
//
//  Cypherpunk look shared with Fully Noded (iOS): terminal green on near-black,
//  monospaced type, square 1pt borders.
//
//  • `.cypherTheme()` at the root of every window: dark, monospaced, green accent,
//    theme background behind lists / text editors.
//  • `.cypherPage()` on a content page: fills it with the background and themes its
//    buttons and group boxes.
//  • `.cypherPanel()` for a bordered card.
//

import SwiftUI

enum Cypher {
    static let bg = Color(red: 0.02, green: 0.035, blue: 0.03)        // near-black, green tint
    static let panel = Color(red: 0.05, green: 0.08, blue: 0.065)     // card
    static let accent = Color(red: 0.25, green: 1.0, blue: 0.48)      // terminal green
    static let line = Color(red: 0.25, green: 1.0, blue: 0.48).opacity(0.45)
    static let dim = Color(red: 0.42, green: 0.62, blue: 0.5)         // muted green-gray
    static let text = Color(red: 0.80, green: 0.95, blue: 0.86)       // pale green
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.28)       // pending / stopped
    static let danger = Color(red: 1.0, green: 0.28, blue: 0.32)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Square bordered button: accent text on a dark panel (or solid accent when `prominent`).
struct CypherButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // One container: a label written as several views (icon + text) would otherwise
        // get the padding / background / border once PER view.
        HStack(spacing: 6) {
            configuration.label
        }
            .font(Cypher.mono(12, weight: .semibold))
            .foregroundStyle(prominent ? Cypher.bg : Cypher.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Rectangle().fill(prominent
                                 ? Cypher.accent.opacity(configuration.isPressed ? 0.75 : 1)
                                 : (configuration.isPressed ? Cypher.accent.opacity(0.18) : Cypher.panel))
            )
            .overlay(Rectangle().stroke(prominent ? Cypher.accent : Cypher.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == CypherButtonStyle {
    static var cypher: CypherButtonStyle { CypherButtonStyle() }
    static var cypherProminent: CypherButtonStyle { CypherButtonStyle(prominent: true) }
}

/// "> LABEL" caption over a bordered panel.
struct CypherGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("> ")
                configuration.label
            }
            .font(Cypher.mono(11, weight: .bold))
            .foregroundStyle(Cypher.accent)
            .textCase(.uppercase)

            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cypher.panel)
        .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
    }
}

/// Section caption: "> TITLE" in the accent colour.
struct CypherCaption: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text("> " + title.uppercased())
            .font(Cypher.mono(11, weight: .bold))
            .foregroundStyle(Cypher.accent)
    }
}

extension View {
    /// Window root: dark, monospaced, green accent, theme background behind scrolling
    /// content (lists, forms, text editors).
    func cypherTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Cypher.accent)
            .fontDesign(.monospaced)
            .foregroundStyle(Cypher.text)
            .scrollContentBackground(.hidden)
            .background(Cypher.bg)
            .toolbarBackground(Cypher.bg, for: .windowToolbar)
    }

    /// A content page: fills the available space with the theme background and themes
    /// its buttons and group boxes.
    func cypherPage() -> some View {
        // One container first: on a Group (or several views) the frame below would be
        // applied to EACH child, giving every child the full height (big gaps).
        VStack {
            self
        }
            .buttonStyle(.cypher)
            .groupBoxStyle(CypherGroupBoxStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Cypher.bg)
    }

    /// Bordered dark card.
    func cypherPanel(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Cypher.panel)
            .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
    }
}
