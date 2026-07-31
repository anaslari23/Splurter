import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Glassmorphic modern titlebar configuration
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true
    self.styleMask.insert(.fullSizeContentView)
    self.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.96)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Window size toggle channel (Full Dashboard vs Compact Floating Phone Mode)
    let channel = FlutterMethodChannel(name: "splurter/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "setCompactMode" {
        let isCompact = (call.arguments as? [String: Any])?["isCompact"] as? Bool ?? false
        let targetSize = isCompact ? CGSize(width: 300, height: 580) : CGSize(width: 880, height: 580)
        var frame = self.frame
        let oldHeight = frame.height
        frame.size = targetSize
        frame.origin.y += (oldHeight - targetSize.height)
        self.setFrame(frame, display: true, animate: true)
        if isCompact {
          self.level = .floating // Stay on top in compact phone floating mode
        } else {
          self.level = .normal
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
