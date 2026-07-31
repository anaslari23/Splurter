import Cocoa
import FlutterMacOS

class ClipboardMonitor {
    private let channel: FlutterMethodChannel
    private var changeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var lastEmittedContent: String = ""

    private var history: [String] = []

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    deinit { stop() }

    func start() {
        if timer != nil { return }
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func getHistory() -> [String] {
        return history
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "read":
            let pasteboard = NSPasteboard.general
            result(["content": readCurrentContent(from: pasteboard) ?? "", "mimeType": currentMimeType(from: pasteboard)])
        case "getHistory":
            result(history)
        case "write":
            guard let args = call.arguments as? [String: Any], let content = args["content"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "content is required", details: nil))
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(content, forType: .string) else {
                result(FlutterError(code: "CLIPBOARD_ERROR", message: "Could not write to clipboard", details: nil))
                return
            }
            addToHistory(content)
            lastEmittedContent = content
            changeCount = pasteboard.changeCount
            result(nil)
        case "startListening":
            start()
            result(nil)
        case "stopListening":
            stop()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        if currentCount != changeCount {
            changeCount = currentCount

            guard let content = readCurrentContent(from: pasteboard) else { return }
            if content == lastEmittedContent { return }
            lastEmittedContent = content
            addToHistory(content)

            channel.invokeMethod("onClipboardChanged", arguments: ["content": content, "mimeType": currentMimeType(from: pasteboard)])
        }
    }

    private func addToHistory(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        history.removeAll(where: { $0 == text })
        history.insert(text, at: 0)
        if history.count > 5 {
            history = Array(history.prefix(5))
        }
    }

    private func readCurrentContent(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string) { return string }
        if let rtfd = pasteboard.data(forType: .rtfd) {
            return "[RTFD data: \(rtfd.count) bytes]"
        }
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiff = image.tiffRepresentation {
            return "[Image: \(tiff.count) bytes]"
        }
        return nil
    }

    private func currentMimeType(from pasteboard: NSPasteboard) -> String {
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) { return "image/png" }
        let types = pasteboard.types ?? []
        if types.contains(.rtf) { return "text/rtf" }
        if types.contains(.html) { return "text/html" }
        return "text/plain"
    }
}
