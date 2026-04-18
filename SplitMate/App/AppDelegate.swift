internal import Auth
import Supabase
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await savePushToken(hex: hex)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("Push registration failed: \(error.localizedDescription)")
        #endif
    }

    private func savePushToken(hex: String) async {
        let client = SupabaseProvider.shared
        guard let session = try? await client.auth.session else { return }
        let service = PushTokenService(client: client)
        try? await service.upsertToken(userId: session.user.id, hexToken: hex)
    }
}
