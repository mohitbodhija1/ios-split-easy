import UIKit
import UserNotifications

@MainActor
final class PushCoordinator {
    static let shared = PushCoordinator()
    private init() {}

    func onSignedIn() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
        }
    }
}
