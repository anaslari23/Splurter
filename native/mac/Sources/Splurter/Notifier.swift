import UserNotifications

/// Shows phone notifications as native macOS banners; Reply / Dismiss go back over the link.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Reply from Mac")
        let dismiss = UNNotificationAction(identifier: "dismiss", title: "Dismiss on phone", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "reply", actions: [reply, dismiss], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "plain", actions: [dismiss], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { ok, err in NSLog("notif auth: \(ok) \(String(describing: err))") }
    }

    func show(_ m: [String: Any]) {
        guard let id = m["id"] as? String else { return }
        let c = UNMutableNotificationContent()
        c.title = m["title"] as? String ?? ""
        c.subtitle = m["app"] as? String ?? ""
        c.body = m["text"] as? String ?? ""
        c.categoryIdentifier = (m["canReply"] as? Bool == true) ? "reply" : "plain"
        c.userInfo = ["id": id]
        c.interruptionLevel = (m["sync"] as? Bool == true) ? .passive : .active // catch-up items arrive quietly
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil)) { NSLog("notif add \(id): \(String(describing: $0))") }
    }

    func remove(_ id: String) { center.removeDeliveredNotifications(withIdentifiers: [id]) }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner, .list]) }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        defer { done() }
        guard let id = r.notification.request.content.userInfo["id"] as? String else { return }
        switch r.actionIdentifier {
        case "reply":
            if let t = (r as? UNTextInputNotificationResponse)?.userText { Link.shared.sendMessage(["t": "reply", "id": id, "text": t]) }
        case "dismiss", UNNotificationDismissActionIdentifier:
            Link.shared.sendMessage(["t": "dismiss", "id": id])
        default: break
        }
    }
}
