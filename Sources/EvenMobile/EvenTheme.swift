import SwiftUI
import EvenCore
#if canImport(CoreText)
import CoreText
#endif

// Design tokens from docs/design/even-play.dc.html + docs/design/README.md.
// The app has its own light/dark palettes and a manual toggle (persisted),
// matching the design's moon button — not the system appearance.

struct EvenPalette: Equatable {
    var bg: Color
    var card: Color
    var ink: Color
    var sub: Color
    var line: Color
    var faint: Color
    var clay: Color
    var teal: Color

    static let light = EvenPalette(
        bg: Color(hex: 0xF6F1E6),
        card: Color(hex: 0xFBF7EE),
        ink: Color(hex: 0x26201A),
        sub: Color(hex: 0x8A7D69),
        line: Color(hex: 0x26201A).opacity(0.14),
        faint: Color(hex: 0x26201A).opacity(0.055),
        clay: Color(hex: 0xA6552F),
        teal: Color(hex: 0x37756D)
    )

    // Dark member colors are the design's oklch lifts, converted to sRGB.
    static let dark = EvenPalette(
        bg: Color(hex: 0x17130F),
        card: Color(hex: 0x211B15),
        ink: Color(hex: 0xEDE5D6),
        sub: Color(hex: 0x9A8F7C),
        line: Color(hex: 0xEDE5D6).opacity(0.15),
        faint: Color(hex: 0xEDE5D6).opacity(0.07),
        clay: Color(hex: 0xCF8E60),
        teal: Color(hex: 0x6BAFA6)
    )

    func member(_ color: MemberColor) -> Color {
        color == .clay ? clay : teal
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Environment plumbing

private struct EvenPaletteKey: EnvironmentKey {
    static let defaultValue = EvenPalette.light
}

extension EnvironmentValues {
    var palette: EvenPalette {
        get { self[EvenPaletteKey.self] }
        set { self[EvenPaletteKey.self] = newValue }
    }
}

// MARK: - Fonts

enum EvenFont {
    static let serifFamily = "Newsreader"
    static let serifItalicFamily = "Newsreader Italic"
    static let sansFamily = "Source Sans 3"

    private static var registered = false

    /// Registers the bundled variable fonts with CoreText. Idempotent.
    static func register() {
        guard !registered else { return }
        registered = true
        #if canImport(CoreText)
        for name in ["Newsreader", "Newsreader-Italic", "SourceSans3", "SourceSans3-Italic"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        #endif
    }

    /// Newsreader — the display/body serif. Roman and italic live in the
    /// same "Newsreader" family; `.italic()` selects the italic face.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        register()
        let base = Font.custom(serifFamily, size: size).weight(weight)
        return italic ? base.italic() : base
    }

    /// Source Sans 3 — caps labels, meta lines, chips.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        register()
        return Font.custom(sansFamily, size: size).weight(weight)
    }
}

// MARK: - Text convenience

extension Text {
    /// Small caps-style label: Source Sans, tracked, uppercased by callers.
    func capsLabel(_ size: CGFloat, tracking: CGFloat = 1.6, weight: Font.Weight = .semibold) -> Text {
        self.font(EvenFont.sans(size, weight)).kerning(tracking)
    }
}

// MARK: - Money formatting

enum EvenFormat {
    static func euros(_ cents: Int) -> String {
        String(format: "€%.2f", Double(cents) / 100)
    }

    static func shortDate(_ isoDay: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: isoDay) else { return isoDay }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    static func capsDate(_ isoDay: String) -> String {
        shortDate(isoDay).uppercased()
    }
}
