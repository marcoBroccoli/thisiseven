import SwiftUI

/// Component-level preview samples (no domain types). Features use EvenCore.PreviewData.
public enum DesignPreviewSupport {
    public static let primaryButtonTitle = "Get started"
    public static let fieldLabel = "Household name"
    public static let fieldValue = "The Attic"
    public static let tagDraft = "Draft"
    public static let listTitle = "Laundry — towels & bedding"
    public static let listMeta = "TODAY · WEEKLY"
    public static let screenEyebrow = "Email & Calendar"
    public static let screenTitle = "Connect Gmail\n& Calendar."

    /// Mid-week beam — a busy pile of light / medium / heavy tasks (weights 1…3).
    /// Ada ahead on admin + chores; Umut catching up on dailies.
    public static let beamScale = EvenBeamScaleConfiguration(
        weekIndex: 12,
        leading: EvenBeamPan(
            name: "Ada",
            percent: 59,
            tone: .clay,
            // laundry², dishes, bins, groceries, water bill, towels, school run…
            pebbleWeights: [2, 1, 3, 2, 1, 2, 3, 1, 2, 1, 2]
        ),
        trailing: EvenBeamPan(
            name: "Umut",
            percent: 41,
            tone: .pine,
            // dishes × n, vacuum, recycling, cook…
            pebbleWeights: [1, 2, 1, 1, 2, 1, 2, 1, 3]
        )
    )

    /// Solo household — trailing pan ghosted, a few of Ada’s first tasks in.
    public static let beamScaleSolo = EvenBeamScaleConfiguration(
        weekIndex: 1,
        leading: EvenBeamPan(
            name: "Ada",
            percent: 100,
            tone: .clay,
            pebbleWeights: [2, 1, 2, 1, 3]
        ),
        trailing: EvenBeamPan(
            name: "— ?",
            percent: 0,
            tone: .pine,
            isGhost: true
        )
    )
}
