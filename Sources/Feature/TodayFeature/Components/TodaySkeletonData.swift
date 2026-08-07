import EvenCore
import Foundation

/// Feature-local skeleton fixtures — never `PreviewData` in production views.
enum TodaySkeletonData {
    static let sectionLabel = "CHORES"
    static let caption = "Loading this week’s balance…"
    static let rows: [(title: String, meta: String)] = [
        ("Placeholder chore title", "TODAY · WEEKLY"),
        ("Another placeholder chore", "TODAY · DAILY"),
        ("Third placeholder chore", "TOMORROW · ONE-OFF"),
    ]
}
