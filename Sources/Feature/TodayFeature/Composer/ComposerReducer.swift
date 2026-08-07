import ComposableArchitecture
import EvenCore
import Foundation

@Reducer
public struct ComposerReducer {
    @ObservableState
    public struct State: Equatable {
        public var title = ""
        public var weight = 2
        public var ownerIsMe = true
        public var section: TaskSection = .chore
        public var recurrence: Recurrence = .none
        public var dueOption: DueOption = .today
        /// When editing a todo whose due day isn't one of the chips (e.g. a
        /// Calendar-imported date), keep the civil day here until the household
        /// picks a chip — `resolvedDueOnISO` prefers this over `dueOption`.
        public var dueOnOverride: String?
        public var endOption: EndOption = .never
        /// Only meaningful while `endOption == .onDate`; kept across a toggle so
        /// reopening the picker restores the household's last pick.
        public var endDate: Date
        /// Only meaningful while `endOption == .afterCount`.
        public var endCount: Int = 6
        /// `nil` = create; set = patch this task id on save.
        public var editingTaskId: UUID?

        /// A one-off has nothing to end, so the row stays hidden until a repeat
        /// is picked. The bound resets with it — an unbounded "Weekly" is the
        /// honest default for a household chore.
        public var showsRepeatEnd: Bool {
            recurrence != .none
        }

        public var isEditing: Bool {
            editingTaskId != nil
        }

        public init(
            title: String = "",
            weight: Int = 2,
            ownerIsMe: Bool = true,
            section: TaskSection = .chore,
            recurrence: Recurrence = .none,
            dueOption: DueOption = .today,
            dueOnOverride: String? = nil,
            endOption: EndOption = .never,
            endDate: Date? = nil,
            endCount: Int = 6,
            editingTaskId: UUID? = nil
        ) {
            self.title = title
            self.weight = weight
            self.ownerIsMe = ownerIsMe
            self.section = section
            self.recurrence = recurrence
            self.dueOption = dueOption
            self.dueOnOverride = dueOnOverride
            self.endOption = endOption
            self.endDate = endDate ?? Self.defaultEndDate()
            self.endCount = endCount
            self.editingTaskId = editingTaskId
        }

        /// Prefill the sheet from an existing Today row.
        public init(editing task: HouseholdTask, meId: UUID?, now: Date = Date()) {
            let due = DueOption.matching(dueOn: task.dueOn, now: now)
            let override: String? = (due == nil) ? task.dueOn : nil
            let end: (EndOption, Date?, Int) = {
                if let count = task.recurrenceCount {
                    return (.afterCount, nil, count)
                }
                if let until = task.recurrenceUntil,
                   let date = Calendar.evenHousehold.evenParseCivilDate(until)
                {
                    return (.onDate, date, 6)
                }
                return (.never, nil, 6)
            }()
            self.init(
                title: task.title,
                weight: task.weight,
                ownerIsMe: task.ownerMemberId == meId,
                section: task.section,
                recurrence: task.recurrence,
                dueOption: due ?? .none,
                dueOnOverride: override,
                endOption: task.recurrence == .none ? .never : end.0,
                endDate: end.1,
                endCount: end.2,
                editingTaskId: task.id
            )
        }

        public func resolvedDueOnISO(now: Date = Date()) -> String? {
            if let dueOnOverride { return dueOnOverride }
            return dueOption.dueOnISO(now: now)
        }

        /// Two months out — far enough that the picker opens on a plausible end
        /// rather than today, which would mean a one-occurrence series.
        static func defaultEndDate(now: Date = Date()) -> Date {
            let calendar = Calendar.evenHousehold
            return calendar.date(byAdding: .month, value: 2, to: calendar.startOfDay(for: now))
                ?? calendar.startOfDay(for: now)
        }

        /// Earliest end the picker allows: the day the series starts. A property
        /// so the view can reach it through the store's dynamic member lookup.
        public var endDateRange: PartialRangeFrom<Date> {
            endDateRange(now: Date())
        }

        public func endDateRange(now: Date) -> PartialRangeFrom<Date> {
            let calendar = Calendar.evenHousehold
            let anchor = resolvedDueOnISO(now: now)
                .flatMap(calendar.evenParseCivilDate) ?? calendar.startOfDay(for: now)
            return anchor...
        }

        /// The `recurrence_until` / `recurrence_count` pair for `TaskDraftBody`.
        public func recurrenceEnd(now _: Date = Date()) -> (until: String?, count: Int?) {
            guard recurrence != .none else { return (nil, nil) }
            switch endOption {
            case .never: return (nil, nil)
            case .onDate: return (Calendar.evenHousehold.evenCivilDateString(from: endDate), nil)
            case .afterCount: return (nil, endCount)
            }
        }
    }

    /// How a repeat stops. Mirrors the three ends in `docs/product/API.md`.
    public enum EndOption: String, CaseIterable, Equatable, Sendable {
        case never
        case onDate
        case afterCount

        /// Reads as a sentence with the section label and the detail control:
        /// "Repeat ends · After · 6 times".
        public var label: String {
            switch self {
            case .never: "Never"
            case .onDate: "On a date"
            case .afterCount: "After"
            }
        }
    }

    /// Due chips mapped to ISO `due_on` for `TaskDraftBody`.
    public enum DueOption: String, CaseIterable, Equatable, Sendable {
        case today
        case tomorrow
        case thisWeek
        case none

        public var label: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .thisWeek: "This week"
            case .none: "No date"
            }
        }

        /// Civil calendar day in the household timezone (`Europe/Amsterdam`), or
        /// `nil` for no date. Uses `yyyy-MM-dd` civil formatting — not
        /// `ISO8601DateFormatter`, which defaults to GMT and shifts local midnight.
        public func dueOnISO(now: Date = Date()) -> String? {
            let cal = Calendar.evenHousehold
            let today = cal.startOfDay(for: now)
            let date: Date? = switch self {
            case .today: today
            case .tomorrow: cal.date(byAdding: .day, value: 1, to: today)
            case .thisWeek:
                // End of the current week (Saturday in ISO-ish household weeks —
                // use Sunday start + 6 days for a stable “this week” tip).
                cal.date(byAdding: .day, value: 6 - ((cal.component(.weekday, from: today) + 5) % 7), to: today)
            case .none: nil
            }
            guard let date else { return nil }
            return cal.evenCivilDateString(from: date)
        }

        /// Maps a stored civil day onto a Due chip. Returns `nil` when the day
        /// isn't one of the presets — caller keeps it as `dueOnOverride`.
        public static func matching(dueOn: String?, now: Date = Date()) -> DueOption? {
            guard let dueOn else { return .none }
            for option in [DueOption.today, .tomorrow, .thisWeek] {
                if option.dueOnISO(now: now) == dueOn { return option }
            }
            return nil
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)

        @CasePathable
        public enum View: Equatable, Sendable {
            case saveTapped
            case cancelTapped
            case selectWeight(Int)
            case selectOwner(Bool)
            case selectSection(TaskSection)
            case selectRecurrence(Recurrence)
            case selectDue(DueOption)
            case selectEnd(EndOption)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .view(.selectWeight(w)):
                state.weight = w
                return .none
            case let .view(.selectOwner(me)):
                state.ownerIsMe = me
                return .none
            case let .view(.selectSection(section)):
                state.section = section
                return .none
            case let .view(.selectRecurrence(recurrence)):
                state.recurrence = recurrence
                // Dropping back to a one-off leaves no series to bound.
                if recurrence == .none { state.endOption = .never }
                return .none
            case let .view(.selectDue(due)):
                state.dueOption = due
                state.dueOnOverride = nil
                // The anchor moved, so an earlier end date may now precede the
                // first occurrence. Pull it forward rather than send an
                // impossible series.
                let earliest = state.endDateRange.lowerBound
                if state.endDate < earliest { state.endDate = earliest }
                return .none
            case let .view(.selectEnd(end)):
                state.endOption = end
                return .none
            case .binding, .view(.saveTapped), .view(.cancelTapped):
                return .none
            }
        }
    }
}
