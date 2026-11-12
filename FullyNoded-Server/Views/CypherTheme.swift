//
//  CypherTheme.swift
//  FullyNoded-Server
//
//  Cypherpunk look shared with Fully Noded (iOS): terminal green on near-black,
//  monospaced type, square 1pt borders.
//
//  • `.cypherTheme()` at the root of every window: dark, monospaced, green accent,
//    theme background behind lists / text editors.
//  • `.cypherPage(palette)` on a content page: fills it with the background and themes its
//    buttons and group boxes, in that page's own colour (CypherPalette: Bitcoin Core orange,
//    Lightning yellow, Nostr magenta, …). `Cypher.accent` and friends resolve from it.
//  • `.cypherPanel()` for a bordered card.
//

import SwiftUI

enum Cypher {
    // Follow the page's palette (CypherPalette, from the environment): each view has its own hue.
    static let bg = CypherStyle(.bg)
    static let panel = CypherStyle(.panel)
    static let accent = CypherStyle(.accent)
    static let line = CypherStyle(.line)
    static let dim = CypherStyle(.dim)
    static let text = CypherStyle(.text)
    // Status colours: the same everywhere.
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.28)       // pending / stopped
    static let danger = Color(red: 1.0, green: 0.28, blue: 0.32)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A view's colours: an accent hue, with the background, card, line, muted and body text
/// derived from it (near-black and pale versions of the same hue).
struct CypherPalette: Equatable {
    let red: Double, green: Double, blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// `amount` of the accent over a base grey.
    private func mix(_ base: Double, _ amount: Double) -> Color {
        Color(red: base + (red - base) * amount, green: base + (green - base) * amount, blue: base + (blue - base) * amount)
    }

    var accent: Color { Color(red: red, green: green, blue: blue) }
    var bg: Color { mix(0.025, 0.05) }
    var panel: Color { mix(0.05, 0.09) }
    var line: Color { accent.opacity(0.45) }
    var dim: Color { mix(0.5, 0.35) }
    var text: Color { mix(0.88, 0.2) }

    func color(_ role: CypherStyle.Role) -> Color {
        switch role {
        case .bg: return bg
        case .panel: return panel
        case .accent: return accent
        case .line: return line
        case .dim: return dim
        case .text: return text
        }
    }

    /// One cool family, each page a small step around sky blue so they feel related (not a
    /// rainbow). Sky blue is also the sidebar, home page and anything without its own.
    static let standard = CypherPalette(0.35, 0.78, 1.0)         // sky blue
    static let silentPayments = standard
    static let bitcoinCore = CypherPalette(0.40, 0.72, 1.0)      // a touch deeper
    static let bitcoinKnots = CypherPalette(0.34, 0.82, 0.96)    // toward cyan
    static let lightning = CypherPalette(0.48, 0.70, 1.0)        // cornflower
    static let joinMarket = CypherPalette(0.30, 0.86, 0.90)      // aqua
    static let explorer = CypherPalette(0.42, 0.80, 0.98)        // ice blue
    static let nostr = CypherPalette(0.56, 0.68, 1.0)            // periwinkle
    static let tor = CypherPalette(0.60, 0.64, 1.0)              // blue-lavender
    static let settings = CypherPalette(0.50, 0.66, 0.92)        // slate blue
    static let help = CypherPalette(0.62, 0.74, 0.86)            // steel
}

/// A theme colour, resolved from the palette of the view it's drawn in.
struct CypherStyle: ShapeStyle {
    enum Role { case bg, panel, accent, line, dim, text }
    let role: Role

    init(_ role: Role) { self.role = role }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        environment.cypherPalette.color(role).resolve(in: environment)
    }
}

private struct CypherPaletteKey: EnvironmentKey {
    static let defaultValue = CypherPalette.standard
}

extension EnvironmentValues {
    var cypherPalette: CypherPalette {
        get { self[CypherPaletteKey.self] }
        set { self[CypherPaletteKey.self] = newValue }
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
                                 ? AnyShapeStyle(Cypher.accent.opacity(configuration.isPressed ? 0.75 : 1))
                                 : (configuration.isPressed ? AnyShapeStyle(Cypher.accent.opacity(0.18)) : AnyShapeStyle(Cypher.panel)))
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
    func cypherPage(_ palette: CypherPalette = .standard) -> some View {
        // One container first: on a Group (or several views) the frame below would be
        // applied to EACH child, giving every child the full height (big gaps).
        VStack {
            self
        }
            .tint(palette.accent)
            .foregroundStyle(Cypher.text)
            .buttonStyle(.cypher)
            .groupBoxStyle(CypherGroupBoxStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Cypher.bg)
            .environment(\.cypherPalette, palette)
    }

    /// Bordered dark card.
    func cypherPanel(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Cypher.panel)
            .overlay(Rectangle().stroke(Cypher.line, lineWidth: 1))
    }
}
