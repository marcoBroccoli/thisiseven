import SwiftUI

public struct EvenPrimaryButton: View {
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
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(EvenTokens.paperRaised)
                .background(EvenTokens.espresso)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(accessibilityId ?? title)
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
