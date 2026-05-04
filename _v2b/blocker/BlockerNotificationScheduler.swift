import Foundation
import UserNotifications

extension Notification.Name {
    static let blockerNotificationAction = Notification.Name("blocker.notification.action")
}

final class BlockerNotificationScheduler {
    private var unblockNotificationIDs: [String] {
        [ScheduledNotification.unblockReady.id]
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func schedule(_ notification: ScheduledNotification, after seconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notification.id])
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelUnblockNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: unblockNotificationIDs)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: unblockNotificationIDs)
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
