import SwiftUI
import EvenCore

// MARK: - Paper grain

#if canImport(UIKit)
import UIKit

private let grainImage: UIImage = {
    let side = 128
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    var rng = SystemRandomNumberGenerator()
    return renderer.image { ctx in
        for y in 0..<side {
            for x in 0..<side where Bool.random(using: &rng) {
                let gray = CGFloat.random(in: 0...1, using: &rng)
                ctx.cgContext.setFillColor(UIColor(white: gray, alpha: 1).cgColor)
                ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }
}()

struct GrainOverlay: View {
    var body: some View {
        Image(uiImage: grainImage)
            .resizable(resizingMode: .tile)
            .opacity(0.05)
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
#else
struct GrainOverlay: View {
    var body: some View { Color.clear.allowsHitTesting(false) }
}
#endif

// MARK: - Ink stamp toast

struct StampToast: View {
    @Environment(\.palette) private var palette
    let message: String

    var body: some View {
        Text(message)
            .capsLabel(11, tracking: 1.5, weight: .bold)
            .foregroundStyle(palette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.bg)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.ink, lineWidth: 2))
            .frame(maxWidth: 320)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.6).combined(with: .opacity),
                removal: .opacity
            ))
    }
}

// MARK: - Check circle (task + trade rows)

struct CheckCircle: View {
    @Environment(\.palette) private var palette
    let done: Bool
    let color: Color
    var size: CGFloat = 27
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(done ? color : palette.line, lineWidth: 1.5)
                    .background(Circle().fill(done ? color : .clear))
                CheckmarkShape()
                    .trim(from: 0, to: done ? 1 : 0)
                    .stroke(Color(hex: 0xFBF7EE),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.48, height: size * 0.48)
                    .animation(.easeOut(duration: 0.25), value: done)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.12))
        return p
    }
}

// MARK: - Owner chip & heft dots

struct OwnerChip: View {
    let member: Member?
    let palette: EvenPalette
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(member.map { palette.member($0.color) } ?? palette.sub)
            .frame(width: size, height: size)
            .overlay(
                Text(member.map { String($0.displayName.prefix(1)).uppercased() } ?? "?")
                    .font(EvenFont.sans(size * 0.45, .bold))
                    .foregroundStyle(Color(hex: 0xFBF7EE))
            )
    }
}

struct HeftDots: View {
    let weight: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<max(1, weight), id: \.self) { _ in
                Circle().fill(color).opacity(0.8).frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Selection pill (owner / reminder options)

struct SelectPill: View {
    @Environment(\.palette) private var palette
    let label: String
    let selected: Bool
    var tint: Color?
    let action: () -> Void

    var body: some View {
        let color = tint ?? palette.ink
        Button(action: action) {
            Text(label)
                .capsLabel(10, tracking: 0.8)
                .foregroundStyle(selected ? color : palette.sub)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? color.opacity(0.14) : .clear))
                .overlay(Capsule().stroke(selected ? color : palette.line, lineWidth: 1.5))
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
    }
}

// MARK: - Buttons

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EvenFont.serif(16, .medium))
                .foregroundStyle(palette.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.ink))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EvenFont.serif(15))
                .foregroundStyle(palette.sub)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Field styling

struct UnderlineField: View {
    @Environment(\.palette) private var palette
    let placeholder: String
    @Binding var text: String
    var serifSize: CGFloat = 17

    var body: some View {
        VStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .font(EvenFont.serif(serifSize))
                .foregroundStyle(palette.ink)
                .textFieldStyle(.plain)
            Rectangle().fill(palette.line).frame(height: 1.5)
        }
    }
}

// MARK: - Screen scaffold helpers

struct ScreenHeader: View {
    @Environment(\.palette) private var palette
    let kicker: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .capsLabel(10, tracking: 1.4)
                .foregroundStyle(palette.sub)
            Text(title)
                .font(EvenFont.serif(26, .medium))
                .foregroundStyle(palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(EvenFont.serif(12.5, italic: true))
                    .foregroundStyle(palette.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FooterAphorism: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        Text(text)
            .font(EvenFont.serif(12.5, italic: true))
            .foregroundStyle(palette.sub)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 14)
    }
}
