import Cocoa
import FlutterMacOS
import Foundation

class FileHandler {
    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickFile":
            openFilePicker(result: result)
        case "saveFileDialog":
            guard let args = call.arguments as? [String: Any],
                  let suggestedName = args["suggestedName"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "suggestedName required", details: nil))
                return
            }
            saveFileDialog(suggestedName: suggestedName, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func openFilePicker(result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                var size: Int = 0
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) as [FileAttributeKey: Any],
                   let fileSize = attrs[.size] as? NSNumber {
                    size = fileSize.intValue
                }
                result([
                    "path": url.path,
                    "name": url.lastPathComponent,
                    "size": size,
                    "mimeType": self.mimeType(for: url),
                ])
            } else {
                result(nil)
            }
        }
    }

    private func saveFileDialog(suggestedName: String, result: @escaping FlutterResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                result(url.path)
            } else {
                result(nil)
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
