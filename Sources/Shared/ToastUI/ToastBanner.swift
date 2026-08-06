import SwiftUI

/// The toast's foreground only — tone dot + message, padded to pill size.
///
/// Kept separate from `ToastBanner` so the Island morph can lay this straight
/// onto the shader blob instead of stacking a second pill on top of it.
struct ToastLabel: View {
    @Environment(\.toastConfiguration) private var configuration

    let toast: Toast

    private var style: ToastStyle {
        configuration.style
    }

    var body: some View {
        HStack(spacing: style.spacing) {
            Circle()
                .fill(style.accent(for: toast.tone))
                .frame(width: style.accentDiameter, height: style.accentDiameter)

            Text(toast.message)
                .font(style.font)
                .foregroundStyle(style.label)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: style.maxTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("toast")
    }
}

/// Standalone pill — used wherever the Island morph isn't driving the shape
/// (devices without a Dynamic Island, previews).
public struct ToastBanner: View {
    @Environment(\.toastConfiguration) private var configuration

    let toast: Toast

    public init(toast: Toast) {
        self.toast = toast
    }

    public var body: some View {
        ToastLabel(toast: toast)
            .background(Capsule(style: .continuous).fill(configuration.style.ink))
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: configuration.style.shadowColor,
                radius: configuration.style.shadowRadius,
                y: configuration.style.shadowOffsetY
            )
    }
}

#Preview("ToastBanner") {
    VStack(spacing: 14) {
        ToastBanner(toast: .init(message: "On the calendar", tone: .success))
        ToastBanner(toast: .init(message: "Skipped for now", tone: .neutral))
        ToastBanner(toast: .init(message: "Couldn’t reach the server", tone: .error))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.93))
}
