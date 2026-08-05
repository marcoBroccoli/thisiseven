import SwiftUI

public struct EvenScreenChrome<Content: View>: View {
    private let eyebrow: String?
    private let title: String
    private let content: Content

    public init(eyebrow: String? = nil, title: String, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(EvenTokens.stone)
            }
            Text(title)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .padding(.top, eyebrow == nil ? 0 : 10)
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 64)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .evenPaperBackground()
    }
}

#Preview("EvenScreenChrome") {
    EvenScreenChrome(
        eyebrow: DesignPreviewSupport.screenEyebrow,
        title: DesignPreviewSupport.screenTitle
    ) {
        Text("Supporting copy for the screen.")
            .font(.system(size: 15.5))
            .foregroundStyle(EvenTokens.stone)
            .padding(.top, 12)
        Spacer()
        EvenPrimaryButton(DesignPreviewSupport.primaryButtonTitle) {}
    }
}
