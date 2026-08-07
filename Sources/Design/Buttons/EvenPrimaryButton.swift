import SwiftUI

public struct EvenPrimaryButton: View {
    /// Maximum continuous rounding for full-width ~50pt CTAs — reads with
    /// sheet / device curvature (not a tight squircle).
    public static var shape: Capsule {
        Capsule()
    }

    private let title: String
    private let action: () -> Void
    private let enabled: Bool
    private let accessibilityId: String?

    public init(
        _ title: String,
        enabled: Bool = true,
        accessibilityId: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.enabled = enabled
        self.accessibilityId = accessibilityId
        self.action = action
    }

    public var body: some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .contentTransition(.numericText())
                .animation(EvenMotion.reveal, value: title)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(EvenTokens.paperRaised)
                // Solid muted fill when disabled. Avoid `.disabled` — SwiftUI fades
                // disabled controls and the paper grain shows through.
                .background(enabled ? EvenTokens.espresso : EvenTokens.stone)
                .clipShape(Self.shape)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        .animation(EvenMotion.reveal, value: enabled)
        .accessibilityIdentifier(accessibilityId ?? title)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
        .accessibilityRemoveTraits(enabled ? [] : .isButton)
    }
}

public struct EvenAppleSignInChrome: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "apple.logo")
            Text("Sign in with Apple")
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("EvenPrimaryButton") {
    EvenPrimaryButton(DesignPreviewSupport.primaryButtonTitle) {}
        .padding()
        .background(EvenTokens.paperRaised)
}

#Preview("EvenAppleSignInChrome") {
    EvenAppleSignInChrome()
        .padding()
        .background(EvenTokens.paperRaised)
}
