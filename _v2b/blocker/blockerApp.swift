import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#endif

@main
struct blockerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BlockerAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(iOS)
final class BlockerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(
            name: .blockerNotificationAction,
            object: response.actionIdentifier
        )
        completionHandler()
    }
}
#endif
