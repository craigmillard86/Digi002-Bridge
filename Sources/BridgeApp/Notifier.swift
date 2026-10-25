import AppKit
import UserNotifications

/// macOS notifications for the few events worth interrupting for. Only works from the
/// app bundle: the notification centre refuses a process without a bundle identifier,
/// and crashes rather than returning an error, so it is never touched outside one.
final class Notifier {
    static let available = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    private var asked = false

    /// Asks for permission the first time it is needed; macOS remembers the answer.
    func post(_ title: String, _ body: String) {
        guard Self.available else { return }
        let centre = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            centre.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if asked { send(); return }
        asked = true
        centre.requestAuthorization(options: [.alert, .sound]) { granted, _ in if granted { send() } }
    }
}
