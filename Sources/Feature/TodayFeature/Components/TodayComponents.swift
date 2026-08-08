#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI
    import UIKit
    import VisualEffects

    // MARK: - Layout tokens

    //
    // One place for Today spacing. Hierarchy:
    //   page*     → applied once on the List
    //   section*  → headers / gaps between List sections
    //   beam*     → scale + caption block
    //   row*      → each task row (and skeleton rows)
    //   marker*   → check + owner circles
    //   empty*    → empty / unavailable states

    private enum TodayLayout {
        // Page — the single horizontal gutter, carried by `todayPaperListRow()`
        static let pageHorizontal: CGFloat = 20
        static let sectionGap: CGFloat = 8

        // Beam header
        static let beamHeight: CGFloat = 240
        static let beamTop: CGFloat = 8
        static let captionTop: CGFloat = 8

        /// Section header
        static let sectionHeaderTop: CGFloat = 10

        // Organize chips (under beam) — Composer chip chrome, exclusive select
        static let organizeTop: CGFloat = 14
        static let organizeChipSpacing: CGFloat = 8
        static let organizeChipHorizontal: CGFloat = 14
        static let organizeChipVertical: CGFloat = 8

        // Task row — padding sits inside the capsule, `rowGap` between capsules
        static let rowVertical: CGFloat = 12
        static let rowHorizontal: CGFloat = 14
        static let rowGap: CGFloat = 6
        static let rowItemSpacing: CGFloat = 12
        static let titleMetaSpacing: CGFloat = 3
        static let trailingClusterSpacing: CGFloat = 8
        static let weightDotSpacing: CGFloat = 2.5
        static let weightDot: CGFloat = 6

        // Markers (check + owner initial)
        static let marker: CGFloat = 24
        static let initialFont: CGFloat = 12
        static let checkTick: CGFloat = 12

        // Empty / unavailable
        // The beam artwork draws fixed chrome for a 240pt canvas (post base at
        // y196, WEEK label at y210) — a shorter frame spills it into the copy.
        static let emptyBeamHeight: CGFloat = beamHeight
        static let emptyStackSpacing: CGFloat = 16
        static let emptySpacerMin: CGFloat = 40
        static let unavailableTop: CGFloat = 48
    }

    // MARK: - Surface

    struct TodayContentSurface: View {
        let summary: Summary?
        let me: Member?
        let partner: Member?
        let isLoading: Bool
        let organizeMode: TodayOrganizeMode
        let onToggle: (UUID) -> Void
        let onEdit: (UUID) -> Void
        let onDelete: (UUID) -> Void
        let onOrganize: (TodayOrganizeMode) -> Void
        let onRefresh: () async -> Void

        private var showSkeleton: Bool {
            isLoading && summary == nil
        }

        var body: some View {
            List {
                if showSkeleton {
                    Section {
                        TodayLoadingSkeleton()
                    }
                } else if let summary {
                    TodayLoadedContent(
                        summary: summary,
                        me: me,
                        partner: partner,
                        organizeMode: organizeMode,
                        onToggle: onToggle,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onOrganize: onOrganize
                    )
                } else {
                    Section {
                        TodaySummaryUnavailable()
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(TodayLayout.sectionGap)
            .environment(\.defaultMinListRowHeight, 0)
            .evenScrollOnPaper()
            .refreshable { await onRefresh() }
            .animation(EvenMotion.reveal, value: showSkeleton)
            .animation(EvenMotion.reveal, value: summary?.week.index)
        }
    }

    struct TodayLoadedContent: View {
        let summary: Summary
        let me: Member?
        let partner: Member?
        let organizeMode: TodayOrganizeMode
        let onToggle: (UUID) -> Void
        let onEdit: (UUID) -> Void
        let onDelete: (UUID) -> Void
        let onOrganize: (TodayOrganizeMode) -> Void

        private var hasTasks: Bool {
            summary.sections.contains { !$0.tasks.isEmpty }
        }

        /// Stable task ids across modes — List moves these instead of fading sections.
        private var rows: [TodayListRow] {
            TodayOrganizer.rows(
                summary: summary,
                mode: organizeMode,
                me: me,
                partner: partner
            )
        }

        var body: some View {
            if !hasTasks {
                Section {
                    TodayEmptyBeam(me: me, partner: partner, weekIndex: summary.week.index)
                }
            } else {
                Section {
                    TodayBeamHeader(summary: summary, me: me, partner: partner)
                    TodayOrganizePills(mode: organizeMode, onSelect: onOrganize)
                }

                Section {
                    ForEach(rows) { row in
                        switch row {
                        case let .header(_, label):
                            TodaySectionHeader(label: label)
                        case let .task(task):
                            TodayTaskRow(
                                task: task,
                                me: me,
                                partner: partner,
                                onToggle: { onToggle(task.id) },
                                onEdit: { onEdit(task.id) },
                                onDelete: { onDelete(task.id) }
                            )
                        }
                    }
                }
            }
        }
    }

    /// Day / Type / Person — Composer chip chrome (espresso fill / stroke), not IG tab bar.
    struct TodayOrganizePills: View {
        let mode: TodayOrganizeMode
        let onSelect: (TodayOrganizeMode) -> Void

        var body: some View {
            HStack(spacing: TodayLayout.organizeChipSpacing) {
                ForEach(TodayOrganizeMode.allCases, id: \.self) { option in
                    TodayOrganizeChip(
                        title: option.pillLabel,
                        selected: mode == option,
                        action: { onSelect(option) }
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.top, TodayLayout.organizeTop)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Organize list")
            .todayPaperListRow()
        }
    }

    struct TodayOrganizeChip: View {
        let title: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .padding(.horizontal, TodayLayout.organizeChipHorizontal)
                    .padding(.vertical, TodayLayout.organizeChipVertical)
                    .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                    .background(selected ? EvenTokens.espresso : Color.clear)
                    .overlay(
                        Capsule().stroke(
                            selected ? Color.clear : EvenTokens.espresso.opacity(0.16),
                            lineWidth: 1.5
                        )
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.evenPlain)
            .animation(EvenMotion.reveal, value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("organize-\(title.lowercased())")
        }
    }

    struct TodaySummaryUnavailable: View {
        var body: some View {
            ContentUnavailableView(
                "Today",
                systemImage: "sun.max",
                description: Text("No summary yet.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, TodayLayout.unavailableTop)
            .todayPaperListRow()
        }
    }

    struct TodayBeamHeader: View {
        let summary: Summary
        let me: Member?
        let partner: Member?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                EvenBeamScale(summary: summary, me: me, partner: partner)
                    .frame(height: TodayLayout.beamHeight)
                    .padding(.top, TodayLayout.beamTop)

                Text(summary.caption)
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.stone)
                    .padding(.top, TodayLayout.captionTop)
                    .contentTransition(.numericText())
                    .animation(EvenMotion.reveal, value: summary.caption)
            }
            .todayPaperListRow()
        }
    }

    struct TodaySectionHeader: View {
        let label: String

        var body: some View {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(EvenTokens.stone)
                .textCase(nil)
                .padding(.top, TodayLayout.sectionHeaderTop)
                .todayPaperListRow()
        }
    }

    // MARK: - Empty beam

    struct TodayEmptyBeam: View {
        let me: Member?
        let partner: Member?
        let weekIndex: Int

        var body: some View {
            VStack(spacing: TodayLayout.emptyStackSpacing) {
                Spacer(minLength: TodayLayout.emptySpacerMin)
                EvenBeamScale(
                    summary: Summary(
                        week: Week(id: UUID(), index: weekIndex, startedOn: ""),
                        // No pebbles — the beam shows the configured 50/50 share
                        // on an empty list; weight-0 fakes still draw a ball.
                        pebbles: [],
                        percentMe: 50,
                        percentPartner: 50,
                        caption: "Nothing on the beam yet.",
                        sections: [],
                        pendingDraftCount: 0
                    ),
                    me: me,
                    partner: partner
                )
                .frame(height: TodayLayout.emptyBeamHeight)
                .allowsHitTesting(false)

                Text("Nothing on the beam yet.")
                    .font(.system(size: 19, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                Text("Add the first chore or errand — tap the + above.")
                    .font(.system(size: 12))
                    .foregroundStyle(EvenTokens.stone)
                    .multilineTextAlignment(.center)
                Spacer(minLength: TodayLayout.emptySpacerMin)
            }
            .frame(maxWidth: .infinity)
            .todayPaperListRow()
        }
    }

    // MARK: - Task row

    struct TodayTaskRow: View {
        let task: HouseholdTask
        let me: Member?
        let partner: Member?
        let onToggle: () -> Void
        let onEdit: () -> Void
        let onDelete: () -> Void

        /// Partner rows stay fully visible — the beam needs both sides on
        /// screen — but they are read-only: no check tap, no Edit / Delete.
        private var canWrite: Bool {
            TodayTaskPermission.canWrite(task, me: me)
        }

        var body: some View {
            // A whole-row `Button` competes with `.swipeActions`' own gesture
            // recognizer on iOS 26's floating swipe buttons — taps land on the
            // row instead of Delete/Edit. Plain tap gesture avoids the conflict.
            HStack(spacing: TodayLayout.rowItemSpacing) {
                TodayTaskCheck(done: task.done, ownerColor: ownerColor, interactive: canWrite)
                VStack(alignment: .leading, spacing: TodayLayout.titleMetaSpacing) {
                    Text(task.title)
                        .font(.system(size: 16, design: .serif))
                        .strikethrough(task.done)
                        .foregroundStyle(EvenTokens.espresso)
                    Text(task.resolvedMetaLine)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(EvenTokens.stone)
                }
                Spacer()
                HStack(spacing: TodayLayout.trailingClusterSpacing) {
                    HStack(spacing: TodayLayout.weightDotSpacing) {
                        ForEach(0 ..< task.weight, id: \.self) { _ in
                            Circle()
                                .fill(ownerColor)
                                .frame(
                                    width: TodayLayout.weightDot,
                                    height: TodayLayout.weightDot
                                )
                        }
                    }
                    ownerAvatar
                }
            }
            .padding(.vertical, TodayLayout.rowVertical)
            .padding(.horizontal, TodayLayout.rowHorizontal)
            .background(TodayRowCapsule(done: task.done))
            .contentShape(Capsule(style: .continuous))
            // `including:` rather than a conditional modifier — same view
            // identity either way, so a row never re-inflates when members land.
            .gesture(
                TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggle()
                },
                including: canWrite ? .all : .none
            )
            .accessibilityAddTraits(canWrite ? .isButton : [])
            .accessibilityHint(readOnlyHint)
            .padding(.vertical, TodayLayout.rowGap / 2)
            .accessibilityIdentifier("check-\(task.title)")
            // Public swipe config is only: edge, full-swipe, role, tint, label.
            // There is no API for button width/height — the system sizes from
            // row height + label (iconOnly keeps iOS 26 from stacking title+icon).
            .swipeActions(edge: .trailing, allowsFullSwipe: canWrite) {
                if canWrite {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .tint(EvenTokens.terracotta)
                        .labelStyle(.iconOnly)

                    Button("Edit", systemImage: "pencil", action: onEdit)
                        .tint(EvenTokens.espresso)
                        .labelStyle(.iconOnly)
                }
            }
            .todayPaperListRow()
        }

        private var readOnlyHint: Text {
            guard !canWrite else { return Text(verbatim: "") }
            let owner = TodayOwnerColor.member(for: task.ownerMemberId, me: me, partner: partner)?
                .displayName ?? "Your partner"
            return Text("\(owner)’s to finish")
        }

        private var ownerColor: Color {
            TodayOwnerColor.color(for: task.ownerMemberId, me: me, partner: partner)
        }

        @ViewBuilder
        private var ownerAvatar: some View {
            if let member = TodayOwnerColor.member(for: task.ownerMemberId, me: me, partner: partner) {
                EvenMemberAvatar(
                    memberId: member.id,
                    displayName: member.displayName,
                    accent: Color(hex: member.color.rgb),
                    hasAvatar: member.hasAvatar,
                    size: TodayLayout.marker,
                    ringWidth: 1.5
                )
            } else {
                Text("?")
                    .font(.system(size: TodayLayout.initialFont, weight: .bold))
                    .foregroundStyle(EvenTokens.paperCard)
                    .frame(width: TodayLayout.marker, height: TodayLayout.marker)
                    .background(Circle().fill(ownerColor))
            }
        }
    }

    /// Raised paper capsule behind a task row. A done row settles back toward the
    /// page paper so open work stays the brightest thing in the list.
    struct TodayRowCapsule: View {
        let done: Bool

        var body: some View {
            Capsule(style: .continuous)
                .fill(done ? EvenTokens.paperRaised : EvenTokens.paperCard)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            EvenTokens.espresso.opacity(done ? 0.05 : 0.08),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: EvenTokens.espresso.opacity(done ? 0 : 0.05),
                    radius: 5,
                    y: 2
                )
                .animation(EvenMotion.reveal, value: done)
        }
    }

    /// Compact row check — Shape + trim (ConnectionsDrawnCheckmark pattern), owner fill when done.
    struct TodayTaskCheck: View {
        let done: Bool
        let ownerColor: Color
        /// A partner's open todo draws a fainter ring — the one honest hint
        /// that this circle is not yours to tick. No lock, no extra chrome.
        var interactive = true

        private var openRingOpacity: Double { interactive ? 0.35 : 0.18 }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(ownerColor.opacity(done ? 0 : openRingOpacity), lineWidth: 1.5)
                    .background(
                        Circle().fill(done ? ownerColor : Color.clear)
                    )
                if done {
                    TodayCheckmarkShape()
                        .stroke(
                            EvenTokens.paperRaised,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: TodayLayout.checkTick, height: TodayLayout.checkTick)
                }
            }
            .frame(width: TodayLayout.marker, height: TodayLayout.marker)
            .animation(EvenMotion.reveal, value: done)
            .accessibilityHidden(true)
        }
    }

    struct TodayCheckmarkShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(
                to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.52)
            )
            path.addLine(
                to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.78)
            )
            path.addLine(
                to: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.22)
            )
            return path
        }
    }

    // MARK: - Skeleton

    struct TodayLoadingSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(EvenTokens.espresso.opacity(0.12))
                    .frame(height: TodayLayout.beamHeight)
                    .padding(.top, TodayLayout.beamTop)

                Text(TodaySkeletonData.caption)
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .padding(.top, TodayLayout.captionTop)

                Text(TodaySkeletonData.sectionLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.5)
                    .padding(.top, TodayLayout.sectionHeaderTop)

                ForEach(Array(TodaySkeletonData.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: TodayLayout.rowItemSpacing) {
                        Circle().stroke(EvenTokens.espresso.opacity(0.35), lineWidth: 1.5)
                            .frame(width: TodayLayout.marker, height: TodayLayout.marker)
                        VStack(alignment: .leading, spacing: TodayLayout.titleMetaSpacing) {
                            Text(row.title)
                                .font(.system(size: 16, design: .serif))
                            Text(row.meta)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.6)
                        }
                        Spacer(minLength: TodayLayout.rowItemSpacing)
                        Text("A")
                            .font(.system(size: TodayLayout.initialFont, weight: .bold))
                            .frame(width: TodayLayout.marker, height: TodayLayout.marker)
                            .background(Circle().fill(EvenTokens.stone))
                    }
                    .padding(.vertical, TodayLayout.rowVertical)
                    .padding(.horizontal, TodayLayout.rowHorizontal)
                    .background(TodayRowCapsule(done: false))
                    .padding(.vertical, TodayLayout.rowGap / 2)
                }
            }
            .foregroundStyle(EvenTokens.espresso)
            .loading(true)
            .accessibilityLabel("Loading today")
            .todayPaperListRow()
        }
    }

    // MARK: - Owner colors

    enum TodayOwnerColor {
        static func member(for ownerMemberId: UUID, me: Member?, partner: Member?) -> Member? {
            if let me, ownerMemberId == me.id { return me }
            if let partner, ownerMemberId == partner.id { return partner }
            return nil
        }

        static func color(for ownerMemberId: UUID, me: Member?, partner: Member?) -> Color {
            if let member = member(for: ownerMemberId, me: me, partner: partner) {
                return Color(hex: member.color.rgb)
            }
            return EvenTokens.stone
        }

        static func initial(for ownerMemberId: UUID, me: Member?, partner: Member?) -> String {
            if let member = member(for: ownerMemberId, me: me, partner: partner),
               let first = member.displayName.first
            {
                return String(first).uppercased()
            }
            return "?"
        }
    }

    // MARK: - List chrome

    fileprivate extension View {
        /// Paper through List rows — owned by each List-row struct, not the call site.
        ///
        /// Replaces `.plain`'s system insets (~11pt vertical, ~20pt leading) with
        /// the page gutter — so the List stays full width (swipe actions reach the
        /// edge) while content sits at `TodayLayout.pageHorizontal`.
        func todayPaperListRow() -> some View {
            listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: TodayLayout.pageHorizontal,
                    bottom: 0,
                    trailing: TodayLayout.pageHorizontal
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

#endif
