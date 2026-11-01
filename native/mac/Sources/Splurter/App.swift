import SwiftUI

@main
struct SplurterApp: App {
    @StateObject private var link = Link()
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                if let qr = link.qr { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 260, height: 260) }
                Text(link.status).font(.headline)
                List(Array(link.log.enumerated()), id: \.offset) { Text($0.element).font(.caption) }.frame(height: 100)
            }
            .padding(20).frame(width: 360)
            .onAppear { link.start(); NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
