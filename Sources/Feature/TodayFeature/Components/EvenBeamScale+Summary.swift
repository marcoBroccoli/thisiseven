import Design
import EvenCore

public extension EvenBeamScale {
    /// Maps a household week summary onto the Design beam primitive.
    ///
    /// Pan tones stay role-based (me = clay / partner = pine) so custom profile
    /// colors don’t fight the beam’s left/right identity; chips and avatars use
    /// each member’s hex elsewhere.
    init(summary: Summary, me: Member?, partner: Member?) {
        self.init(
            configuration: EvenBeamScaleConfiguration(
                weekIndex: summary.week.index,
                leading: EvenBeamPan(
                    name: me?.displayName ?? "You",
                    percent: summary.percentMe,
                    tone: .clay,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == me?.id }
                        .map(\.weight)
                ),
                trailing: EvenBeamPan(
                    name: partner?.displayName ?? "\u{2014} ?",
                    percent: summary.percentPartner,
                    tone: .pine,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == partner?.id }
                        .map(\.weight),
                    isGhost: partner == nil
                )
            )
        )
    }
}
