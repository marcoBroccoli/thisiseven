import Design
import EvenCore

public extension EvenBeamScale {
    /// Maps a household week summary onto the Design beam primitive.
    init(summary: Summary, me: Member?, partner: Member?) {
        self.init(
            configuration: EvenBeamScaleConfiguration(
                weekIndex: summary.week.index,
                leading: EvenBeamPan(
                    name: me?.displayName ?? "You",
                    percent: summary.percentMe,
                    tone: Self.tone(me?.color) ?? .clay,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == me?.id }
                        .map(\.weight)
                ),
                trailing: EvenBeamPan(
                    name: partner?.displayName ?? "\u{2014} ?",
                    percent: summary.percentPartner,
                    tone: Self.tone(partner?.color) ?? .pine,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == partner?.id }
                        .map(\.weight),
                    isGhost: partner == nil
                )
            )
        )
    }

    private static func tone(_ memberColor: MemberColor?) -> EvenBeamPanTone? {
        switch memberColor {
        case .clay: .clay
        case .teal: .pine
        case .none: nil
        }
    }
}
