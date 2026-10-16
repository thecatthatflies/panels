import SwiftUI
import AppKit

// MARK: - Color helpers

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Accent palette (per panel override)

enum AccentID: String, Codable, CaseIterable, Identifiable {
    case theme, wood, taupe, granite, lavender, sky, ember
    var id: String { rawValue }

    var label: String {
        switch self {
        case .theme: return "Theme"
        case .wood: return "Olive Wood"
        case .taupe: return "Taupe"
        case .granite: return "Granite"
        case .lavender: return "Lavender"
        case .sky: return "Pale Sky"
        case .ember: return "Ember"
        }
    }

    var hex: UInt32? {
        switch self {
        case .theme: return nil
        case .wood: return 0xB08B6E
        case .taupe: return 0xB7A7A1
        case .granite: return 0x6FA39F
        case .lavender: return 0x8896AB
        case .sky: return 0xC5D5E4
        case .ember: return 0xD9825B
        }
    }
}

// MARK: - Theme tokens

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let window: UInt32
    let surface: UInt32
    let surfaceRaised: UInt32
    let text: UInt32
    let textMuted: UInt32
    let textFaint: UInt32
    let accent: UInt32
    let ansi: [UInt32]          // 16 terminal colors
    let termBackground: UInt32
    let termForeground: UInt32

    var windowC: Color { Color(hex: window) }
    var surfaceC: Color { Color(hex: surface) }
    var raisedC: Color { Color(hex: surfaceRaised) }
    var textC: Color { Color(hex: text) }
    var mutedC: Color { Color(hex: textMuted) }
    var faintC: Color { Color(hex: textFaint) }
    var accentC: Color { Color(hex: accent) }
    var hairline: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.08) }
    var hairlineStrong: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.16) }
    var hover: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06) }
    var pressed: Color { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10) }
    var shadow: Color { isDark ? Color.black.opacity(0.45) : Color(hex: 0x1B2433, alpha: 0.16) }

    func accent(_ override: AccentID) -> Color {
        if let h = override.hex { return Color(hex: h) }
        return accentC
    }
    func accentNS(_ override: AccentID) -> NSColor {
        NSColor(hex: override.hex ?? accent)
    }

    // Template palette: 7E6551 Olive Wood, 938581 Taupe, 466362 Granite,
    // 8896AB Lavender Grey, C5D5E4 Pale Sky.

    static let granite = Theme(
        id: "granite", name: "Granite", isDark: true,
        window: 0x141E1D, surface: 0x1B2927, surfaceRaised: 0x233433,
        text: 0xDCE7F0, textMuted: 0x8FA3AD, textFaint: 0x587270,
        accent: 0xB08B6E,
        ansi: [0x233433, 0xD98A7E, 0x7FBF9E, 0xD4B27A, 0x8AA3C8, 0xB5A0C4, 0x6FB3B0, 0xC5D5E4,
               0x466362, 0xE8A396, 0x9AD2B4, 0xE6C897, 0xA9BCDB, 0xCBB9D6, 0x93CBC8, 0xEEF4F9],
        termBackground: 0x172322, termForeground: 0xCFDCE6)

    static let paleSky = Theme(
        id: "paleSky", name: "Pale Sky", isDark: false,
        window: 0xC5D5E4, surface: 0xE3ECF4, surfaceRaised: 0xF4F8FB,
        text: 0x1E2B2A, textMuted: 0x466362, textFaint: 0x8896AB,
        accent: 0x7E6551,
        ansi: [0x1E2B2A, 0xB5483E, 0x2F7D5B, 0x9A6B1C, 0x3E5E96, 0x7A5C96, 0x2B7A78, 0xC5D5E4,
               0x466362, 0xCF6558, 0x3F9672, 0xB5832F, 0x5679B3, 0x967AB0, 0x3F9593, 0xF4F8FB],
        termBackground: 0xF1F6FA, termForeground: 0x1E2B2A)

    static let taupe = Theme(
        id: "taupe", name: "Taupe", isDark: true,
        window: 0x211C1A, surface: 0x2B2523, surfaceRaised: 0x362E2B,
        text: 0xEBE4E0, textMuted: 0xA09390, textFaint: 0x6E625F,
        accent: 0x8896AB,
        ansi: [0x362E2B, 0xE0897C, 0x86BFA0, 0xD9B67E, 0x8FA6CC, 0xB8A3C6, 0x74B5B2, 0xD6CCC8,
               0x5E524F, 0xEEA397, 0xA0D2B7, 0xEACB9B, 0xADBFDD, 0xCDBCD8, 0x97CCC9, 0xF5F0ED],
        termBackground: 0x251F1D, termForeground: 0xDDD4D0)

    static let slate = Theme(
        id: "slate", name: "Lavender", isDark: true,
        window: 0x161B24, surface: 0x1E2430, surfaceRaised: 0x272F3E,
        text: 0xD9E3EF, textMuted: 0x8896AB, textFaint: 0x566075,
        accent: 0xB08B6E,
        ansi: [0x272F3E, 0xDB8A80, 0x82BE9E, 0xD6B47C, 0x8AA3CC, 0xB6A2C8, 0x72B4B4, 0xC5D5E4,
               0x4A5568, 0xEAA498, 0x9CD1B5, 0xE8C99A, 0xA9BDDE, 0xCCBDDA, 0x95CBCB, 0xEFF4F9],
        termBackground: 0x191F29, termForeground: 0xCDD9E6)

    static let all: [Theme] = [.granite, .paleSky, .taupe, .slate]
    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .granite }
}

// MARK: - Appearance (global, observable)

enum ThemeChoice: String, Codable, CaseIterable, Identifiable {
    case auto, granite, paleSky, taupe, slate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .granite: return "Granite"
        case .paleSky: return "Pale Sky"
        case .taupe: return "Taupe"
        case .slate: return "Lavender"
        }
    }
}

@Observable
final class Appearance {
    static let shared = Appearance()

    var choice: ThemeChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "theme"); refreshSystem() }
    }
    var translucency: Double {
        didSet { UserDefaults.standard.set(translucency, forKey: "translucency") }
    }
    var gap: Double {
        didSet { UserDefaults.standard.set(gap, forKey: "gap") }
    }
    var cornerRadius: Double {
        didSet { UserDefaults.standard.set(cornerRadius, forKey: "radius") }
    }
    var systemDark: Bool = true

    init() {
        let d = UserDefaults.standard
        choice = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .auto
        translucency = d.object(forKey: "translucency") as? Double ?? 0.82
        gap = d.object(forKey: "gap") as? Double ?? 8
        cornerRadius = d.object(forKey: "radius") as? Double ?? 14
        refreshSystem()
    }

    func refreshSystem() {
        let name = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        systemDark = (name ?? .darkAqua) == .darkAqua
    }

    func theme(for space: Space) -> Theme {
        if let id = space.themeID, let t = Theme.all.first(where: { $0.id == id }) { return t }
        return theme
    }

    var theme: Theme {
        switch choice {
        case .auto: return systemDark ? .granite : .paleSky
        case .granite: return .granite
        case .paleSky: return .paleSky
        case .taupe: return .taupe
        case .slate: return .slate
        }
    }
}

// MARK: - Typography

enum Typo {
    static let regular = "InstrumentSans-Regular"
    static let bold = "InstrumentSans-Bold"
    static let italic = "InstrumentSans-Italic"
    static let boldItalic = "InstrumentSans-BoldItalic"

    static func ui(_ size: CGFloat, bold isBold: Bool = false) -> Font {
        .custom(isBold ? bold : regular, fixedSize: size)
    }

    static func nsUI(_ size: CGFloat, bold isBold: Bool = false) -> NSFont {
        NSFont(name: isBold ? bold : regular, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)
    }

    static func registerBundledFonts() {
        let bundle = Bundle.main
        guard let urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Editor font families

enum EditorFont: String, Codable, CaseIterable, Identifiable {
    case instrument, system, serif, rounded, mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instrument: return "Instrument Sans"
        case .system: return "SF Pro"
        case .serif: return "New York"
        case .rounded: return "SF Rounded"
        case .mono: return "SF Mono"
        }
    }

    var isMono: Bool { self == .mono }

    func regular(_ size: CGFloat) -> NSFont {
        switch self {
        case .instrument: return NSFont(name: Typo.regular, size: size) ?? .systemFont(ofSize: size)
        case .system: return .systemFont(ofSize: size, weight: .regular)
        case .serif: return design(.serif, size: size, weight: .regular)
        case .rounded: return design(.rounded, size: size, weight: .regular)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    func bold(_ size: CGFloat) -> NSFont {
        switch self {
        case .instrument: return NSFont(name: Typo.bold, size: size) ?? .boldSystemFont(ofSize: size)
        case .system: return .systemFont(ofSize: size, weight: .bold)
        case .serif: return design(.serif, size: size, weight: .bold)
        case .rounded: return design(.rounded, size: size, weight: .bold)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }

    func italic(_ size: CGFloat) -> NSFont {
        switch self {
        case .instrument: return NSFont(name: Typo.italic, size: size) ?? italicize(regular(size))
        default: return italicize(regular(size))
        }
    }

    func boldItalic(_ size: CGFloat) -> NSFont {
        switch self {
        case .instrument: return NSFont(name: Typo.boldItalic, size: size) ?? italicize(bold(size))
        default: return italicize(bold(size))
        }
    }

    private func italicize(_ f: NSFont) -> NSFont {
        NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
    }

    private func design(_ d: NSFontDescriptor.SystemDesign, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(d) {
            return NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }
}
