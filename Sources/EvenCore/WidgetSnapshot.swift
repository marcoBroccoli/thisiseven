import Foundation

// A tiny, self-contained snapshot the iOS app publishes to a shared App Group
// so the WidgetKit extension can render without touching the network. Kept in
// EvenCore so both the app (writer) and the widget (reader) share one type.
//
// The app writes this after every summary/todos change and asks WidgetKit to
// reload timelines; the widget's TimelineProvider reads it (falling back to a
// gallery placeholder when nothing has been published yet).
public struct EvenWidgetSnapshot: Codable, Sendable, Equatable {
    /// Shared App Group both the app and the extension are entitled to.
    public static let appGroupID = "group.com.umuryavuz.even"
    /// Key under which the JSON blob lives in the shared UserDefaults suite.
    public static let defaultsKey = "even.widget.snapshot.v1"

    /// One side of the balance beam (a household member).
    public struct Side: Codable, Sendable, Equatable {
        public var name: String
        public var initial: String
        public var color: MemberColor
        public var share: Int          // 0–100 for this member this week
        public var done: Int           // completions landed this week

        public init(name: String, initial: String, color: MemberColor, share: Int, done: Int) {
            self.name = name
            self.initial = initial
            self.color = color
            self.share = share
            self.done = done
        }
    }

    /// An upcoming household item (task or draft) shown in "Up Next" rows.
    public struct UpNext: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var typeMeta: String    // e.g. "CHORE", "ADMIN", "REVIEW"
        public var ownerColor: MemberColor
        public var ownerInitial: String
        public var when: String        // pre-formatted, e.g. "TODAY", "JUL 21"
        public var amountCents: Int?
        public var gcal: Bool          // mirrors the shared Google Calendar

        public init(id: String, title: String, typeMeta: String, ownerColor: MemberColor,
                    ownerInitial: String, when: String, amountCents: Int?, gcal: Bool) {
            self.id = id
            self.title = title
            self.typeMeta = typeMeta
            self.ownerColor = ownerColor
            self.ownerInitial = ownerInitial
            self.when = when
            self.amountCents = amountCents
            self.gcal = gcal
        }
    }

    public var weekIndex: Int
    public var clay: Side              // the clay (terracotta) member — left arm
    public var teal: Side              // the teal member — right arm
    public var hasPartner: Bool        // false ⇒ teal arm rendered ghosted
    public var leader: String          // the week caption ("Leaning …")
    public var leftToday: Int          // open items due today
    public var upcoming: [UpNext]      // up to 4, soonest first
    public var generatedAt: Date

    public init(weekIndex: Int, clay: Side, teal: Side, hasPartner: Bool, leader: String,
                leftToday: Int, upcoming: [UpNext], generatedAt: Date) {
        self.weekIndex = weekIndex
        self.clay = clay
        self.teal = teal
        self.hasPartner = hasPartner
        self.leader = leader
        self.leftToday = leftToday
        self.upcoming = upcoming
        self.generatedAt = generatedAt
    }

    // MARK: - Shared-container I/O

    public static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Publishes the snapshot to the shared App Group. No-op if the suite is
    /// unavailable (e.g. running without the entitlement in a unit test).
    public func write() {
        guard let store = Self.sharedDefaults(),
              let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: Self.defaultsKey)
    }

    /// Reads the last published snapshot, or nil if none exists yet.
    public static func read() -> EvenWidgetSnapshot? {
        guard let store = sharedDefaults(),
              let data = store.data(forKey: defaultsKey),
              let snap = try? JSONDecoder().decode(EvenWidgetSnapshot.self, from: data)
        else { return nil }
        return snap
    }

    /// Gallery / no-data placeholder (design's sample values).
    public static let placeholder = EvenWidgetSnapshot(
        weekIndex: 7,
        clay: .init(name: "Ada", initial: "A", color: .clay, share: 58, done: 9),
        teal: .init(name: "Umut", initial: "U", color: .teal, share: 42, done: 6),
        hasPartner: true,
        leader: "Leaning Ada — mostly the admin and the remembering.",
        leftToday: 3,
        upcoming: [
            .init(id: "1", title: "Water the plants", typeMeta: "CHORE",
                  ownerColor: .teal, ownerInitial: "U", when: "TODAY", amountCents: nil, gcal: false),
            .init(id: "2", title: "Electricity bill", typeMeta: "ADMIN",
                  ownerColor: .clay, ownerInitial: "A", when: "JUL 21", amountCents: 8940, gcal: true),
            .init(id: "3", title: "Dentist — Umut", typeMeta: "CALENDAR",
                  ownerColor: .teal, ownerInitial: "U", when: "JUL 22", amountCents: nil, gcal: true),
            .init(id: "4", title: "Call the landlord", typeMeta: "ADMIN",
                  ownerColor: .clay, ownerInitial: "A", when: "JUL 23", amountCents: nil, gcal: false)
        ],
        generatedAt: Date(timeIntervalSince1970: 0)
    )
}
