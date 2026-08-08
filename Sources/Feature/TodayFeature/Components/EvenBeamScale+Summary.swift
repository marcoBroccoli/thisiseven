import Design
import EvenCore

public extension EvenBeamScale {
    /// Maps a household week summary onto the Design beam primitive.
    ///
    /// Pans wear each member's chosen profile colour (Umur 2026-08-08) —
    /// change yours in Profile and the pebbles, labels and percents follow.
    /// The role tones are only the fallback while members are still loading.
    init(summary: Summary, me: Member?, partner: Member?) {
        self.init(
            configuration: EvenBeamScaleConfiguration(
                weekIndex: summary.week.index,
                leading: EvenBeamPan(
                    name: me?.displayName ?? "You",
                    percent: summary.percentMe,
                    tone: me.map { .custom($0.color.rgb) } ?? .clay,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == me?.id }
                        .map(\.weight)
                ),
                trailing: EvenBeamPan(
                    name: partner?.displayName ?? "\u{2014} ?",
                    percent: summary.percentPartner,
                    tone: partner.map { .custom($0.color.rgb) } ?? .pine,
                    pebbleWeights: summary.pebbles
                        .filter { $0.memberId == partner?.id }
                        .map(\.weight),
                    isGhost: partner == nil
                )
            )
        )
    }
}
