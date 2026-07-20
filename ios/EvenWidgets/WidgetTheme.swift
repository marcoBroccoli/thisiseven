import SwiftUI
import EvenCore

// Design tokens ported from docs/design + Sources/EvenMobile/EvenTheme.swift.
// The "paper" widgets deliberately use the cream/ink light palette (the app's
// signature look); the Today card uses the ink/cream dark palette from the mock.

struct WidgetPalette: Equatable {
    var bg: Color
    var card: Color
    var ink: Color
    var sub: Color
    var line: Color
    var faint: Color
    var clay: Color
    var teal: Color

    func member(_ color: MemberColor) -> Color { color == .clay ? clay : teal }

    static let paper = WidgetPalette(
        bg: .hex(0xFBF7EE), card: .hex(0xF6F1E6),
        ink: .hex(0x26201A), sub: .hex(0x8A7D69),
        line: Color.hex(0x26201A).opacity(0.14), faint: Color.hex(0x26201A).opacity(0.06),
        clay: .hex(0xA6552F), teal: .hex(0x37756D))

    static let ink = WidgetPalette(
        bg: .hex(0x211B15), card: .hex(0x17130F),
        ink: .hex(0xEDE5D6), sub: .hex(0x9A8F7C),
        line: Color.hex(0xEDE5D6).opacity(0.15), faint: Color.hex(0xEDE5D6).opacity(0.07),
        clay: .hex(0xCF8E60), teal: .hex(0x6BAFA6))
}

extension Color {
    static func hex(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

// Newsreader (serif, numbers/leader) + Source Sans 3 (labels), bundled via the
// extension's UIAppFonts. Font.custom falls back to the system face if a name
// fails to resolve, so the widget never renders blank.
enum WidgetFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom("Newsreader", size: size).weight(weight)
    }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        Font.custom("Source Sans 3", size: size).weight(weight)
    }
}

enum WidgetFormat {
    static func euros(_ cents: Int) -> String {
        String(format: "€%.2f", Double(cents) / 100)
    }
}

extension Text {
    func caps(_ size: CGFloat, tracking: CGFloat = 1.6, weight: Font.Weight = .semibold) -> Text {
        self.font(WidgetFont.sans(size, weight)).kerning(tracking)
    }
}
