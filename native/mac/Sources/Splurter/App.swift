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
    @State private var number = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(link.connectedName.map { "Connected to \($0)" } ?? (link.devices.isEmpty ? "No phone paired" : "Waiting for phone…"),
                  systemImage: link.connectedName == nil ? "wifi.slash" : "checkmark.circle.fill")
                .font(.headline)

            ForEach(link.devices) { d in
                HStack { Image(systemName: "iphone"); Text(d.name); Spacer(); Button("Forget") { link.forget(d.id) }.buttonStyle(.link) }
            }

            if let c = link.call {
                HStack {
                    Image(systemName: "phone.fill")
                    Text(c.state == "ringing" ? "Incoming: \(c.name.isEmpty ? c.number : c.name)" : "On call: \(c.name.isEmpty ? c.number : c.name)")
                    Spacer()
                    if c.state == "ringing" { Button("Answer") { link.sendMessage(["t": "call_answer"]) } }
                    Button(c.state == "ringing" ? "Decline" : "End") { link.sendMessage(["t": "call_end"]) }
                }
            }

            if link.connectedName != nil {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Phone number", text: $number)
                    TextField("Message", text: $message)
                    HStack {
                        Button("Send file…") {
                            let p = NSOpenPanel(); p.canChooseFiles = true; p.allowsMultipleSelection = true
                            if p.runModal() == .OK { p.urls.forEach(link.sendFile) }
                        }
                        Button("Call") { link.sendMessage(["t": "dial", "number": number]) }
                        Button("Send text") { link.sendMessage(["t": "sms_send", "to": number, "text": message]); message = "" }
                            .disabled(number.isEmpty || message.isEmpty)
                    }
                }.textFieldStyle(.roundedBorder)
            }

            if let t = link.transfer { Label(t, systemImage: "arrow.up.arrow.down") .font(.caption) }

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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in // drop files on the popover to send
            for p in providers { _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { link.sendFile(u) } } }
            return true
        }
    }
}
