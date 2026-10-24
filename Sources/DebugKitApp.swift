import SwiftUI
import UserNotifications

@main
struct DebugKitApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Notifier.requestPermission()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
