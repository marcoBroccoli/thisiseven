import WidgetKit
import SwiftUI
import EvenCore

struct EvenEntry: TimelineEntry {
    let date: Date
    let snapshot: EvenWidgetSnapshot
}

/// Reads the App Group snapshot the app publishes. Falls back to the design
/// placeholder for the gallery and the never-launched state.
struct EvenProvider: TimelineProvider {
    func placeholder(in context: Context) -> EvenEntry {
        EvenEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EvenEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (EvenWidgetSnapshot.read() ?? .placeholder)
        completion(EvenEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EvenEntry>) -> Void) {
        let snapshot = EvenWidgetSnapshot.read() ?? .placeholder
        let entry = EvenEntry(date: .now, snapshot: snapshot)
        // The app reloads timelines on every data change; this is just a
        // safety refresh so a static day still rolls "today" forward.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// One "Up Next" line: owner dot, serif title, type/when meta, optional amount.
struct UpNextRow: View {
    let item: EvenWidgetSnapshot.UpNext
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(palette.member(item.ownerColor)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(WidgetFont.serif(13, .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.typeMeta).caps(8, tracking: 1).foregroundStyle(palette.sub)
                    if item.gcal {
                        Image(systemName: "calendar")
                            .font(.system(size: 7))
                            .foregroundStyle(palette.sub)
                    }
                    Text(item.when).caps(8, tracking: 1).foregroundStyle(palette.sub)
                }
            }
            Spacer(minLength: 4)
            if let amount = item.amountCents {
                Text(WidgetFormat.euros(amount))
                    .font(WidgetFont.serif(12, .medium))
                    .foregroundStyle(palette.ink)
            }
        }
    }
}

/// The "AdaPct / UmutPct" pair shown under a beam.
struct SharePair: View {
    let snapshot: EvenWidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            side(snapshot.clay, muted: false)
            Spacer()
            side(snapshot.teal, muted: !snapshot.hasPartner)
        }
    }

    private func side(_ member: EvenWidgetSnapshot.Side, muted: Bool) -> some View {
        let color = muted ? palette.sub : palette.member(member.color)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(member.initial).caps(9, tracking: 1).foregroundStyle(palette.sub)
            Text("\(member.share)")
                .font(WidgetFont.serif(26, .medium))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
