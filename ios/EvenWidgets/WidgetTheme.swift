import SwiftUI
import EvenCore

// Design tokens for the original Even widget language.
// ADA (terracotta) = the clay member / left pan. UMUT (teal) = the partner /
// right pan. INK/SUB/CREAM are the paper palette; the "Today" card and the lock
// accessories use the dark card (INK bg, CREAM text, sub-on-dark).
enum WT {
    static let ada       = Color.hex(0xA6552F)   // terracotta — clay / left pan
    static let umut      = Color.hex(0x37756D)   // teal — right pan
    static let ink       = Color.hex(0x26201A)
    static let sub       = Color.hex(0x8A7D69)
    static let cream     = Color.hex(0xFBF7EE)
    static let darkBg    = Color.hex(0x26201A)
    static let subOnDark = Color.hex(0xB7A98F)
    static let onDark    = Color.hex(0xE9E1D2)    // brighter body text on dark
    static let lineOnCream = Color.hex(0x26201A).opacity(0.10)
    static let ringTrack   = Color.hex(0xFBF7EE).opacity(0.14)

    static func member(_ c: MemberColor) -> Color { c == .clay ? ada : umut }
}

/// A per-card palette. Cream is the signature paper look; dark is the Today card
/// and lock accessories. Member colours are fixed (ADA terracotta / UMUT teal).
struct WidgetPalette: Equatable {
    var bg: Color
    var ink: Color
    var sub: Color
    var line: Color
    /// Ink colour used to stroke the beam furniture (cream on a dark card).
    var beamInk: Color

    func member(_ c: MemberColor) -> Color { WT.member(c) }

    static let cream = WidgetPalette(
        bg: WT.cream, ink: WT.ink, sub: WT.sub,
        line: WT.lineOnCream, beamInk: WT.ink)

    static let dark = WidgetPalette(
        bg: WT.darkBg, ink: WT.cream, sub: WT.subOnDark,
        line: Color.hex(0xFBF7EE).opacity(0.14), beamInk: WT.cream)
}

extension Color {
    static func hex(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

// Newsreader (serif — numbers, titles, leader copy) + Source Sans 3 (labels).
// Both bundled via the extension's UIAppFonts; Font.custom falls back to the
// system face if a name fails to resolve so the widget never renders blank.
enum WidgetFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let f = Font.custom("Newsreader", size: size).weight(weight)
        return italic ? f.italic() : f
    }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        Font.custom("Source Sans 3", size: size).weight(weight)
    }
}

enum WidgetFormat {
    static func euros(_ cents: Int) -> String {
        let v = Double(cents) / 100
        // Whole euros drop the cents; otherwise two decimals.
        return v == v.rounded() ? String(format: "€%.0f", v) : String(format: "€%.2f", v)
    }
}

extension Text {
    /// Uppercase label styling: Source Sans 3, ~0.14em letter-spacing.
    func caps(_ size: CGFloat, em: CGFloat = 0.14, weight: Font.Weight = .semibold) -> Text {
        self.font(WidgetFont.sans(size, weight)).tracking(size * em)
    }
    /// Explicit-tracking variant (kept for Provider.swift's helpers).
    func caps(_ size: CGFloat, tracking: CGFloat, weight: Font.Weight = .semibold) -> Text {
        self.font(WidgetFont.sans(size, weight)).tracking(tracking)
    }
}

/// A round owner chip: filled member colour with the member's initial in cream.
struct OwnerChip: View {
    let color: Color
    let initial: String
    var size: CGFloat = 20
    var muted: Bool = false

    var body: some View {
        Circle()
            .fill(color.opacity(muted ? 0.4 : 1))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(WidgetFont.sans(size * 0.5, .bold))
                    .foregroundStyle(WT.cream)
            )
    }
}

// MARK: - Leader copy

enum Leader {
    /// The design's leader rule, using the real member names.
    static func copy(_ snap: EvenWidgetSnapshot) -> String {
        let ada = snap.clay, umut = snap.teal
        if abs(ada.share - 50) < 6 { return "Dead even this week" }
        return ada.share > 50 ? "\(ada.name)'s a little ahead" : "\(umut.name)'s a little ahead"
    }
}
