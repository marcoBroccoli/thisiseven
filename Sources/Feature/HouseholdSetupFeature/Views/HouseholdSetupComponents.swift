import Design
import SwiftUI

struct PathChoiceButton: View {
    let title: String
    let subtitle: String
    let emphasized: Bool
    let accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(EvenTokens.stone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EvenTokens.espresso)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasized ? EvenTokens.paperCard : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // `.plain` only hits opaque content unless we declare the full card shape.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }
}

struct InviteCodeTiles: View {
    let code: String

    var body: some View {
        let chars = Array(code)
        GeometryReader { geo in
            let count = max(chars.count, 1)
            let spacing = HouseholdSetupChrome.Tile.spacing
            let tileWidth = min(
                HouseholdSetupChrome.Tile.width,
                max(28, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            )
            let tileHeight = tileWidth * (
                HouseholdSetupChrome.Tile.height / HouseholdSetupChrome.Tile.width
            )
            let fontSize = min(27, tileWidth * 0.6)

            HStack(spacing: spacing) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: fontSize, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .frame(width: tileWidth, height: tileHeight)
                        .background(EvenTokens.paperCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(EvenTokens.espresso.opacity(0.2), lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: HouseholdSetupChrome.Tile.height)
        .frame(maxWidth: .infinity)
    }
}

struct SharePrimaryButton: View {
    let title: String
    let item: String

    var body: some View {
        ShareLink(item: item) {
            HStack(spacing: 9) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .serif))
            }
            .foregroundStyle(EvenTokens.paperRaised)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(EvenTokens.espresso)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct TextContinueLink: View {
    let title: String
    let accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(EvenTokens.stone)
                .underline(pattern: .solid, color: EvenTokens.stone.opacity(0.55))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(accessibilityId)
    }
}

struct CalloutCard: View {
    let eyebrow: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
            Text(message)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(HouseholdSetupChrome.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EvenTokens.espresso.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct WaitingPartnerCard: View {
    let code: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("YOUR PARTNER ISN'T IN YET")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer(minLength: 0)
                Circle()
                    .fill(EvenTokens.pine.opacity(0.5))
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 12) {
                Text(code ?? "————")
                    .font(.system(size: 25, weight: .medium, design: .serif))
                    .tracking(5.5)
                    .foregroundStyle(EvenTokens.espresso)
                Spacer(minLength: 0)
                if let code {
                    ShareLink(item: code) {
                        Text("RESEND")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(EvenTokens.paperRaised)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(EvenTokens.espresso)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(EvenTokens.paperCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
