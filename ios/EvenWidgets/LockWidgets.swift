import WidgetKit
import SwiftUI
import EvenCore

// Lock-screen accessories. These render in the system's tinted/vibrant style, so
// they lean on shape + text; the split ring keeps its ADA/UMUT proportions.

struct LockView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: EvenWidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Even · \(snapshot.leftToday) due today", systemImage: "scalemass")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                SplitRing(snapshot: snapshot, lineWidth: 5, center: .miniBeam)
            }
            .widgetAccentable()

        case .accessoryRectangular:
            rectangular

        default:
            Text("Even")
        }
    }

    @ViewBuilder private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UP NEXT").caps(8)
            if let item = snapshot.upcoming.first {
                HStack(spacing: 5) {
                    OwnerChip(color: WT.member(item.ownerColor), initial: item.ownerInitial, size: 14)
                        .widgetAccentable()
                    Text(item.title).font(WidgetFont.serif(15, .medium)).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("\(item.typeMeta) · \(item.when)").caps(8)
                    Spacer(minLength: 4)
                    if let amount = item.amountCents {
                        Text(WidgetFormat.euros(amount))
                            .font(WidgetFont.serif(12, .medium)).monospacedDigit()
                    }
                }
            } else {
                Text("Nothing queued").font(WidgetFont.serif(14, .regular, italic: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
