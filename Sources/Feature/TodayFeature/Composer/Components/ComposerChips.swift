#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI

    /// Shared selection chrome for Composer chips.
    /// Selected = espresso fill + paper text; unselected = clear + light espresso stroke.
    private enum ComposerChipStyle {
        static let unselectedStroke = EvenTokens.espresso.opacity(0.16)
        static let strokeWidth: CGFloat = 1.5
        static let labelFont: Font = .system(size: 11, weight: .semibold)
        static let tracking: CGFloat = 0.8
        static let horizontalPad: CGFloat = 14
        static let verticalPad: CGFloat = 8
        static let identityDot: CGFloat = 6
    }

    /// Owner chip — espresso selection chrome; terracotta/pine identity via a small dot only.
    struct ComposerOwnerChip: View {
        let label: String
        let accent: Color
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(
                            width: ComposerChipStyle.identityDot,
                            height: ComposerChipStyle.identityDot
                        )
                    Text(label.uppercased())
                        .font(ComposerChipStyle.labelFont)
                        .tracking(ComposerChipStyle.tracking)
                }
                .padding(.horizontal, ComposerChipStyle.horizontalPad)
                .padding(.vertical, ComposerChipStyle.verticalPad)
                .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                .background(selected ? EvenTokens.espresso : Color.clear)
                .overlay(
                    Capsule().stroke(
                        selected ? Color.clear : ComposerChipStyle.unselectedStroke,
                        lineWidth: ComposerChipStyle.strokeWidth
                    )
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(EvenMotion.reveal, value: selected)
        }
    }

    struct ComposerHeftChip: View {
        let weight: Int
        let selected: Bool
        let action: () -> Void

        private let cornerRadius: CGFloat = 12

        var body: some View {
            Button(action: action) {
                VStack(spacing: 5) {
                    HStack(spacing: 2.5) {
                        ForEach(0 ..< weight, id: \.self) { _ in
                            Circle()
                                .fill(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(height: 12)
                    Text(weight == 1 ? "Light" : weight == 2 ? "Medium" : "Heavy")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(selected ? EvenTokens.espresso : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            selected ? EvenTokens.espresso : ComposerChipStyle.unselectedStroke,
                            lineWidth: ComposerChipStyle.strokeWidth
                        )
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .animation(EvenMotion.reveal, value: selected)
        }
    }

    struct ComposerChoiceChip: View {
        let title: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title.uppercased())
                    .font(ComposerChipStyle.labelFont)
                    .tracking(ComposerChipStyle.tracking)
                    .padding(.horizontal, ComposerChipStyle.horizontalPad)
                    .padding(.vertical, ComposerChipStyle.verticalPad)
                    .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                    .background(selected ? EvenTokens.espresso : Color.clear)
                    .overlay(
                        Capsule().stroke(
                            selected ? Color.clear : ComposerChipStyle.unselectedStroke,
                            lineWidth: ComposerChipStyle.strokeWidth
                        )
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(EvenMotion.reveal, value: selected)
        }
    }

    /// "Until when?" for a repeat — the three ends from `docs/product/API.md`,
    /// with only the picked one's detail control on screen. Hidden entirely for a
    /// one-off, so a simple todo never pays for the schedule vocabulary.
    struct ComposerRepeatEndSection: View {
        let option: ComposerReducer.EndOption
        @Binding var date: Date
        @Binding var count: Int
        let dateRange: PartialRangeFrom<Date>
        let select: (ComposerReducer.EndOption) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ComposerSectionLabel(text: "Repeat ends")
                FlowWrap(spacing: 8) {
                    ForEach(ComposerReducer.EndOption.allCases, id: \.self) { end in
                        ComposerChoiceChip(title: end.label, selected: option == end) {
                            select(end)
                        }
                    }
                }
                .padding(.top, 4)

                if option == .onDate {
                    ComposerDateChip(date: $date, range: dateRange)
                        .padding(.top, 10)
                }
                if option == .afterCount {
                    ComposerCountStepper(count: $count)
                        .padding(.top, 10)
                }
            }
        }
    }

    /// Last day of a bounded repeat, drawn in the Composer chip language.
    ///
    /// `.compact` `DatePicker` paints a cool grey system capsule that fights the
    /// cream paper, and there is no API to clear it. So the chip is ours and the
    /// system control rides invisibly on top — `.destinationOver` keeps it
    /// tappable (and keeps its calendar popover) while drawing nothing.
    struct ComposerDateChip: View {
        @Binding var date: Date
        let range: PartialRangeFrom<Date>

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = Calendar.evenHousehold.timeZone
            formatter.dateFormat = "MMM d, yyyy"
            return formatter
        }()

        var body: some View {
            Text(Self.formatter.string(from: date).uppercased())
                .font(ComposerChipStyle.labelFont)
                .tracking(ComposerChipStyle.tracking)
                .foregroundStyle(EvenTokens.espresso)
                .padding(.horizontal, ComposerChipStyle.horizontalPad)
                .padding(.vertical, ComposerChipStyle.verticalPad)
                .overlay(
                    Capsule().stroke(
                        ComposerChipStyle.unselectedStroke,
                        lineWidth: ComposerChipStyle.strokeWidth
                    )
                )
                .overlay {
                    DatePicker("", selection: $date, in: range, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .blendMode(.destinationOver)
                }
                .contentShape(Capsule())
                .animation(EvenMotion.reveal, value: date)
                .accessibilityIdentifier("task-repeat-until")
        }
    }

    /// Occurrence count — a stepper rather than a keyboard, because the honest
    /// range for a household chore is small and typing invites 400s.
    struct ComposerCountStepper: View {
        @Binding var count: Int

        private static let range = 1 ... 52
        private let cornerRadius: CGFloat = 12

        var body: some View {
            HStack(spacing: 12) {
                stepButton(systemName: "minus", enabled: count > Self.range.lowerBound) {
                    count = max(Self.range.lowerBound, count - 1)
                }
                Text("\(count) \(count == 1 ? "time" : "times")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EvenTokens.espresso)
                    .contentTransition(.numericText())
                    .frame(minWidth: 72)
                stepButton(systemName: "plus", enabled: count < Self.range.upperBound) {
                    count = min(Self.range.upperBound, count + 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
            )
            .animation(EvenMotion.reveal, value: count)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("task-repeat-count")
        }

        private func stepButton(
            systemName: String,
            enabled: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    // Solid muted ink, never a system disabled fade over paper.
                    .foregroundStyle(enabled ? EvenTokens.espresso : EvenTokens.stone)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(enabled)
            .accessibilityLabel(systemName == "plus" ? "One more time" : "One fewer time")
        }
    }

    struct ComposerSectionLabel: View {
        let text: String

        var body: some View {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 12)
        }
    }

    #if DEBUG
        /// The repeat-end row on its own — the Composer sheet preview clips it
        /// below the fold.
        private struct ComposerRepeatEndPreview: View {
            @State var option: ComposerReducer.EndOption
            @State private var date = Date().addingTimeInterval(60 * 60 * 24 * 60)
            @State private var count = 6

            var body: some View {
                ComposerRepeatEndSection(
                    option: option,
                    date: $date,
                    count: $count,
                    dateRange: Date()...
                ) { option = $0 }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EvenTokens.paperRaised)
            }
        }

        #Preview("Composer · repeat ends after") {
            ComposerRepeatEndPreview(option: .afterCount)
        }

        // The date variant earns its own preview: a system `DatePicker` is the
        // one control here that can read off-brand over paper.
        #Preview("Composer · repeat ends on a date") {
            ComposerRepeatEndPreview(option: .onDate)
        }
    #endif
#endif
