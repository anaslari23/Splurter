import AppKit
import UserNotifications

/// Shows phone notifications as native macOS banners; Reply / Dismiss go back over the link.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()

    /// Phone app icons, cached by Android package name.
    static func iconURL(_ pkg: String) -> URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Splurter/icons")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(pkg + ".png")
    }

    func setup() {
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Reply from Mac")
        let dismiss = UNNotificationAction(identifier: "dismiss", title: "Dismiss on phone", options: [])
        let answer = UNNotificationAction(identifier: "answer", title: "Answer", options: [])
        let decline = UNNotificationAction(identifier: "decline", title: "Decline", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "call", actions: [answer, decline], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "reply", actions: [reply, dismiss], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "plain", actions: [dismiss], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        if let pkg = m["pkg"] as? String, FileManager.default.fileExists(atPath: Self.iconURL(pkg).path) {
            // The system moves attachment files into its own store, so hand it a copy.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            try? FileManager.default.copyItem(at: Self.iconURL(pkg), to: tmp)
            if let a = try? UNNotificationAttachment(identifier: "icon", url: tmp, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]) { c.attachments = [a] }
        }
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// Incoming calls are one banner with id "call", replaced as the number/name arrive and removed on idle.
    func call(_ c: Link.Call) {
        guard c.state == "ringing" else { return remove("call") }
        let n = UNMutableNotificationContent()
        n.title = c.name.isEmpty ? (c.number.isEmpty ? "Incoming call" : c.number) : c.name
        n.subtitle = "Incoming call"; n.body = c.name.isEmpty ? "" : c.number
        n.categoryIdentifier = "call"; n.sound = .default
        center.add(UNNotificationRequest(identifier: "call", content: n, trigger: nil))
    }

    func received(_ url: URL) {
        let n = UNMutableNotificationContent()
        n.title = "Received \(url.lastPathComponent)"; n.body = "Saved to Downloads — click to show"; n.userInfo = ["path": url.path]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
    }

    func remove(_ id: String) { center.removeDeliveredNotifications(withIdentifiers: [id]) }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner, .list]) }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        defer { done() }
        switch r.actionIdentifier {
        case "answer": Link.shared.sendMessage(["t": "call_answer"]); return
        case "decline": Link.shared.sendMessage(["t": "call_end"]); return
        default: break
        }
        if let path = r.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]); return
        }
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
