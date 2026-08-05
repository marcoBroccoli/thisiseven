import SwiftUI

public struct EvenListRow<Accessory: View>: View {
    private let title: String
    private let meta: String?
    private let accessory: Accessory

    public init(title: String, meta: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.meta = meta
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                if let meta {
                    Text(meta.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(EvenTokens.stone)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 4)
    }
}

public extension EvenListRow where Accessory == EmptyView {
    init(title: String, meta: String? = nil) {
        self.init(title: title, meta: meta) { EmptyView() }
    }
}

#Preview("EvenListRow") {
    EvenListRow(
        title: DesignPreviewSupport.listTitle,
        meta: DesignPreviewSupport.listMeta
    ) {
        EvenTag("2", tone: .neutral)
    }
    .padding()
    .background(EvenTokens.paperRaised)
}
