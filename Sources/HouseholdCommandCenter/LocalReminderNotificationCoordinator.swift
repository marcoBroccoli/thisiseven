import Foundation
import HouseholdCore
import UserNotifications

enum LocalReminderNotificationState: Equatable {
    case needsPermission
    case denied
    case scheduled(Int)
    case unavailable(String)

    var statusText: String {
        switch self {
        case .needsPermission:
            "Enable notifications to receive local reminders for open household work."
        case .denied:
            "Notifications are off in system Settings."
        case .scheduled(let count):
            count == 0 ? "No upcoming local reminders need scheduling." : "\(count) local reminder(s) scheduled."
        case .unavailable(let message):
            "Reminder scheduling failed: \(message)"
        }
    }
}

final class LocalReminderNotificationCoordinator {
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "HouseholdCommandCenter.reminder."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestPermissionAndSchedule(
        drafts: [InboxDraft],
        household: HouseholdContext
    ) async -> LocalReminderNotificationState {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return .denied }
            return await scheduleIfAuthorized(drafts: drafts, household: household)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func scheduleIfAuthorized(
        drafts: [InboxDraft],
        household: HouseholdContext
    ) async -> LocalReminderNotificationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return await replaceScheduledReminders(drafts: drafts, household: household)
        case .denied:
            return .denied
        case .notDetermined:
            return .needsPermission
        @unknown default:
            return .unavailable("Unknown notification authorization status.")
        }
    }

    private func replaceScheduledReminders(
        drafts: [InboxDraft],
        household: HouseholdContext
    ) async -> LocalReminderNotificationState {
        let plans = Array(LocalReminderPlanner.plans(drafts: drafts, household: household).prefix(64))
        center.removePendingNotificationRequests(withIdentifiers: await existingReminderIdentifiers())

        do {
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.threadIdentifier = plan.draftID.uuidString

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: identifierPrefix + plan.id,
                    content: content,
                    trigger: trigger
                )
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
