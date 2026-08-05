import EvenCore
import SwiftUI

@main
struct EvenWatchApp: App {
    var body: some Scene {
        WindowGroup {
            EvenWatchRootView()
        }
    }
}

struct EvenWatchRootView: View {
    private var snapshot: EvenWidgetSnapshot {
        EvenWidgetSnapshot.read() ?? .placeholder
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Even")
                .font(.headline)
            HStack {
                Text("\(snapshot.clay.share)%")
                    .foregroundStyle(Color(red: 0.65, green: 0.33, blue: 0.18))
                Text("·")
                Text("\(snapshot.teal.share)%")
                    .foregroundStyle(Color(red: 0.22, green: 0.46, blue: 0.43))
            }
            .font(.title3)
            Text(snapshot.leader)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding()
    }
}
