import SwiftUI

public struct EvenTag: View {
    private let text: String
    private let tone: Tone

    public enum Tone: Sendable {
        case neutral, terracotta, pine
    }

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: EvenTokens.stone
        case .terracotta: EvenTokens.terracotta
        case .pine: EvenTokens.pine
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: EvenTokens.espresso.opacity(0.06)
        case .terracotta: EvenTokens.terracotta.opacity(0.12)
        case .pine: EvenTokens.pine.opacity(0.12)
        }
    }
}

#Preview("EvenTag") {
    HStack {
        EvenTag(DesignPreviewSupport.tagDraft, tone: .terracotta)
        EvenTag("Chore", tone: .neutral)
        EvenTag("Teal", tone: .pine)
    }
    .padding()
    .background(EvenTokens.paperRaised)
}
