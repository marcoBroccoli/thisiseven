import Foundation
import EvenCore

#if canImport(UserNotifications)
import UserNotifications

enum TodoReminderNotificationState: Equatable {
    case needsPermission
    case denied
    case scheduled(Int)
    case unavailable(String)

    var statusText: String {
        switch self {
        case .needsPermission:
            return "Turn on notifications for a quiet nudge when a dated todo is due."
        case .denied:
            return "Notifications are off for Even in iPhone Settings."
        case .scheduled(let count):
            return count == 0
                ? "Reminders are on. No upcoming dated todos need a nudge."
                : "\(count) upcoming todo reminder\(count == 1 ? "" : "s") scheduled on this phone."
        case .unavailable(let message):
            return "Reminder setup failed: \(message)"
        }
    }

    var isAuthorized: Bool {
        if case .scheduled = self { return true }
        return false
    }
}

/// Device-local delivery for calendar-derived todo occurrences. The server and
/// Google Calendar stay authoritative; this only mirrors the next reminders on
/// the phone that enables it.
@MainActor
final class TodoReminderNotificationCoordinator {
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "Even.todo-reminder."
    private let maximumPlans = 48

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func status() async -> TodoReminderNotificationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            let count = await existingReminderIdentifiers().count
            return .scheduled(count)
        case .denied:
            return .denied
        case .notDetermined:
            return .needsPermission
        @unknown default:
            return .unavailable("Unknown notification permission state.")
        }
    }

    func requestAuthorization() async -> TodoReminderNotificationState {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted ? await status() : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func replaceScheduledReminders(items: [CalendarItem]) async -> TodoReminderNotificationState {
        let current = await status()
        guard current.isAuthorized else { return current }

        let plans = Array(TodoReminderPlanner.plans(items: items).prefix(maximumPlans))
        center.removePendingNotificationRequests(withIdentifiers: await existingReminderIdentifiers())

        do {
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.threadIdentifier = plan.calendarItemID
                content.userInfo = ["calendar_item_id": plan.calendarItemID,
                                    "occurrence_on": plan.occurrenceOn]

                let components = Calendar.autoupdatingCurrent.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifierPrefix + plan.id,
                                                    content: content, trigger: trigger)
                try await center.add(request)
            }
            return .scheduled(plans.count)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func existingReminderIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
    }
}
#else
enum TodoReminderNotificationState: Equatable {
    case needsPermission
    case denied
    case scheduled(Int)
    case unavailable(String)

    var statusText: String { "Local notifications are unavailable on this device." }
    var isAuthorized: Bool { false }
}

@MainActor
final class TodoReminderNotificationCoordinator {
    func status() async -> TodoReminderNotificationState { .unavailable("Unsupported device.") }
    func requestAuthorization() async -> TodoReminderNotificationState { await status() }
    func replaceScheduledReminders(items: [CalendarItem]) async -> TodoReminderNotificationState {
        await status()
    }
}
#endif
