import WidgetKit
import SwiftUI
import EvenCore

// Lock-screen accessories. These render in the system's tinted/vibrant style,
// so they lean on shape + text rather than the paper palette.

struct LockView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.ink   // accessory rendering ignores exact hues

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Even · \(snapshot.leftToday) due today", systemImage: "circle.lefthalf.filled")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                SplitRing(snapshot: snapshot, palette: p, lineWidth: 5)
                Text("\(snapshot.clay.share)")
                    .font(WidgetFont.serif(15, .medium))
                    .minimumScaleFactor(0.6)
            }
            .widgetAccentable()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("UP NEXT").caps(9, tracking: 1.6)
                if let item = snapshot.upcoming.first {
                    Text(item.title)
                        .font(WidgetFont.serif(15, .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.when).caps(9, tracking: 1)
                        if let amount = item.amountCents {
                            Text("·").caps(9)
                            Text(WidgetFormat.euros(amount)).font(WidgetFont.serif(12, .medium))
                        }
                    }
                } else {
                    Text("Nothing queued").font(WidgetFont.serif(14).italic())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            Text("Even")
        }
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenLock", provider: EvenProvider()) { entry in
            LockView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Even")
        .description("Balance ring, due-today count, and the next thing due.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
