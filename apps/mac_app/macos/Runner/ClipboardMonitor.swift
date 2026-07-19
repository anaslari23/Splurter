import Cocoa
import FlutterMacOS

class ClipboardMonitor {
    private let channel: FlutterMethodChannel
    private var changeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var lastEmittedContent: String = ""

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        start()
    }

    deinit { stop() }

    func start() {
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true,
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        if currentCount != changeCount {
            changeCount = currentCount

            guard let content = readCurrentContent(from: pasteboard) else { return }
            if content == lastEmittedContent { return }
            lastEmittedContent = content

            channel.invokeMethod("onClipboardChanged", arguments: ["content": content, "mimeType": currentMimeType(from: pasteboard)])
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
