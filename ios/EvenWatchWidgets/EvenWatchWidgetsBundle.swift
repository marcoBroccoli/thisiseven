import EvenCore
import SwiftUI
import WidgetKit

@main
struct EvenWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EvenWatchBalanceWidget()
    }
}

struct EvenWatchBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenWatchBalance", provider: EvenWatchBalanceProvider()) { entry in
            VStack(spacing: 2) {
                Text("\(entry.clay)% / \(entry.teal)%")
                    .font(.headline)
                Text(entry.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Even")
        .description("This week's balance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct EvenWatchBalanceProvider: TimelineProvider {
    func placeholder(in _: Context) -> EvenWatchBalanceEntry {
        .from(snapshot: .placeholder)
    }

    func getSnapshot(in _: Context, completion: @escaping (EvenWatchBalanceEntry) -> Void) {
        completion(.from(snapshot: EvenWidgetSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<EvenWatchBalanceEntry>) -> Void) {
        let entry = EvenWatchBalanceEntry.from(snapshot: EvenWidgetSnapshot.read() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

struct EvenWatchBalanceEntry: TimelineEntry {
    let date: Date
    let clay: Int
    let teal: Int
    let caption: String

    static func from(snapshot: EvenWidgetSnapshot) -> EvenWatchBalanceEntry {
        EvenWatchBalanceEntry(
            date: .now,
            clay: snapshot.clay.share,
            teal: snapshot.teal.share,
            caption: snapshot.leader
        )
    }
}
