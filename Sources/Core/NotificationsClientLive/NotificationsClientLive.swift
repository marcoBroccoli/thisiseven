import Dependencies
import Foundation
import NotificationsClient
import UserNotifications

extension NotificationsClient: DependencyKey {
    public static let liveValue = NotificationsClient(
        requestAuthorization: {
            let center = UNUserNotificationCenter.current()
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        },
        scheduleReminders: {
            // Wire TodoReminderPlanning + UNUserNotificationCenter in refine pass.
        }
    )
}
