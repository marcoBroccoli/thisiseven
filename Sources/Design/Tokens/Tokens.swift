import SwiftUI

/// Design tokens from `docs/even-design-system/` + `docs/design/README.md`.
///
/// Grow this target into the shared Design primitive catalog (Buttons /
/// FormFields / ListItem / Tags / chrome / typography helpers) — see Personal
/// recipe §3. Features compose Design; do not invent a parallel component vocabulary.
public enum EvenTokens {
    public static let paperGround = Color(hex: 0xE9E1D2)
    public static let paperRaised = Color(hex: 0xF6F1E6)
    public static let paperCard = Color(hex: 0xFBF7EE)
    public static let espresso = Color(hex: 0x26201A)
    public static let espressoDeep = Color(hex: 0x211B15)
    public static let terracotta = Color(hex: 0xA6552F)
    public static let terracottaHover = Color(hex: 0xA0522D)
    public static let pine = Color(hex: 0x37756D)
    public static let stone = Color(hex: 0x8A7D69)
    public static let taupe = Color(hex: 0xB8AC99)
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview("EvenTokens") {
    HStack(spacing: 8) {
        swatch(EvenTokens.paperRaised)
        swatch(EvenTokens.espresso)
        swatch(EvenTokens.terracotta)
        swatch(EvenTokens.pine)
        swatch(EvenTokens.stone)
    }
    .padding()
    .background(EvenTokens.paperGround)
}

private func swatch(_ color: Color) -> some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(color)
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(EvenTokens.espresso.opacity(0.15), lineWidth: 1)
        )
}
