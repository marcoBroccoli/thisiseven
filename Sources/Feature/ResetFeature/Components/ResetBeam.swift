#if os(iOS)
    import Design
    import EvenCore

    /// Summary → beam mapping for the ritual.
    ///
    /// Today owns its own mapper (`EvenBeamScale+Summary`) and Design stays
    /// domain-free on purpose, so the ritual carries its own — it needs a second
    /// shape anyway: the *emptied* beam the pour animates to. Pan tones stay
    /// role-based (me = clay, partner = pine) to match Today exactly.
    enum ResetBeam {
        static func configuration(
            weekIndex: Int,
            summary: Summary?,
            me: Member?,
            partner: Member?,
            emptied: Bool = false
        ) -> EvenBeamScaleConfiguration {
            let minePebbles = emptied
                ? []
                : (summary?.pebbles.filter { $0.memberId == me?.id }.map(\.weight) ?? [])
            let theirPebbles = emptied
                ? []
                : (summary?.pebbles.filter { $0.memberId == partner?.id }.map(\.weight) ?? [])

            return EvenBeamScaleConfiguration(
                weekIndex: weekIndex,
                leading: EvenBeamPan(
                    name: me?.displayName ?? "You",
                    percent: emptied ? 50 : (summary?.percentMe ?? 50),
                    tone: .clay,
                    pebbleWeights: minePebbles
                ),
                trailing: EvenBeamPan(
                    name: partner?.displayName ?? "\u{2014} ?",
                    percent: emptied ? 50 : (summary?.percentPartner ?? 50),
                    tone: .pine,
                    pebbleWeights: theirPebbles,
                    isGhost: partner == nil
                )
            )
        }
    }
#endif
