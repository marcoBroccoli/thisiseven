import CalendarClient
import Dependencies
import EvenCore
import Foundation

extension CalendarClient: DependencyKey {
    public static let liveValue = CalendarClient(
        window: { from, to in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.calendar(from: from, to: to)
        },
        sync: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.syncCalendar()
        }
    )
}
