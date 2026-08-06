import SwiftUI

/// Official Google “G” (standard color) from Google Identity / branding CDN.
/// Use on Connect / Sign-in CTAs — keep original colors (not a template).
public struct EvenGoogleGMark: View {
    public init() {}

    public var body: some View {
        Image("GoogleG", bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}

#Preview("EvenGoogleGMark") {
    EvenGoogleGMark()
        .frame(width: 24, height: 24)
        .padding()
        .background(EvenTokens.paperCard)
}
