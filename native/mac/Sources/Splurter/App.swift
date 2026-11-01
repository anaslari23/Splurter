import ServiceManagement
import SwiftUI

@main
struct SplurterApp: App {
    @ObservedObject private var link = Link.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        Notifier.shared.setup()
        Link.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Splurter", systemImage: link.connectedName == nil ? "iphone.slash" : "iphone.radiowaves.left.and.right") {
            MenuView(link: link)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var link: Link

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(link.connectedName.map { "Connected to \($0)" } ?? (link.devices.isEmpty ? "No phone paired" : "Waiting for phone…"),
                  systemImage: link.connectedName == nil ? "wifi.slash" : "checkmark.circle.fill")
                .font(.headline)

            ForEach(link.devices) { d in
                HStack { Image(systemName: "iphone"); Text(d.name); Spacer(); Button("Forget") { link.forget(d.id) }.buttonStyle(.link) }
            }

            if link.pairing {
                if let qr = link.qr { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 220, height: 220).frame(maxWidth: .infinity) }
                Text("Open Splurter on your phone and tap Scan.").font(.caption).foregroundStyle(.secondary)
            }
            Button(link.pairing ? "Cancel" : "Pair a new phone") { link.pairing.toggle() }

            if !link.log.isEmpty { Text(link.log.joined(separator: "\n")).font(.caption2).foregroundStyle(.secondary) }
            Divider()
            Toggle("Open at login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }))
            Button("Quit Splurter") { NSApp.terminate(nil) }
        }
        .padding(16).frame(width: 280)
    }
}
