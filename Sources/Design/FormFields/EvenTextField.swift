import SwiftUI

public struct EvenTextField: View {
    private let label: String
    private let accessibilityId: String?
    @Binding private var text: String

    public init(_ label: String, text: Binding<String>, accessibilityId: String? = nil) {
        self.label = label
        self.accessibilityId = accessibilityId
        _text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(EvenTokens.stone)
            TextField("", text: $text)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(EvenTokens.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier(accessibilityId ?? label)
        }
    }
}

#Preview("EvenTextField") {
    @Previewable @State var text = DesignPreviewSupport.fieldValue
    EvenTextField(DesignPreviewSupport.fieldLabel, text: $text)
        .padding()
        .background(EvenTokens.paperRaised)
}
