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

        Window("Phone screen", id: "mirror") { MirrorView() }
            .defaultSize(width: 340, height: 740)

        // First run: open straight to pairing. Afterwards it's only opened from the menu.
        Window("Welcome to Splurter", id: "welcome") { WelcomeView(link: link) }
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(link.devices.isEmpty ? .presented : .suppressed)
    }
}

// MARK: - Menu-bar popover

struct MenuView: View {
    @ObservedObject var link: Link
    @Environment(\.openWindow) private var openWindow
    @State private var showDial = false
    @State private var number = ""
    @State private var message = ""

    private var connected: Bool { link.connectedName != nil }
    private var phoneName: String { link.connectedName ?? link.devices.first?.name ?? "No phone paired" }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if link.devices.isEmpty {
                    emptyState
                } else {
                    if let c = link.call { callCard(c) }
                    actions
                    if showDial { dialForm }
                    if let t = link.transfer { Label(t, systemImage: "arrow.up.arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
                    activity
                }
            }.padding(16)
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 340)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in // drop files anywhere on the popover to send
            for p in providers { _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { link.sendFile(u) } } }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(connected ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                Image(systemName: "iphone").font(.title3).foregroundStyle(connected ? .green : .secondary)
            }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(phoneName).font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(connected ? .green : .orange).frame(width: 7, height: 7)
                    Text(connected ? "Connected · encrypted" : link.devices.isEmpty ? "Pair your phone to get started" : "Looking for your phone…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let d = link.devices.first {
                Menu {
                    Button("Pair another phone") { openPairing() }
                    Button("Forget \(d.name)", role: .destructive) { link.forget(d.id) }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Scan once, stay connected").font(.headline)
            Text("Pair your Android phone with a QR code. No account, no cloud.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Pair a phone") { openPairing() }.buttonStyle(.borderedProminent).controlSize(.large)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private func callCard(_ c: Link.Call) -> some View {
        let who = c.name.isEmpty ? c.number : c.name
        return HStack(spacing: 10) {
            Image(systemName: "phone.fill").foregroundStyle(.white).frame(width: 34, height: 34).background(.green, in: Circle())
            VStack(alignment: .leading) {
                Text(who.isEmpty ? "Unknown caller" : who).font(.headline)
                Text(c.state == "ringing" ? "Incoming call" : "On call").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if c.state == "ringing" { Button("Answer") { link.sendMessage(["t": "call_answer"]) }.tint(.green).buttonStyle(.borderedProminent) }
            Button(c.state == "ringing" ? "Decline" : "End") { link.sendMessage(["t": "call_end"]) }.tint(.red).buttonStyle(.bordered)
        }
        .padding(12).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ActionTile(icon: "doc.badge.plus", label: "Send file", enabled: connected) {
                let p = NSOpenPanel(); p.canChooseFiles = true; p.allowsMultipleSelection = true
                if p.runModal() == .OK { p.urls.forEach(link.sendFile) }
            }
            ActionTile(icon: "rectangle.on.rectangle", label: "Mirror", enabled: connected) {
                Mirror.shared.state = "waiting"
                openWindow(id: "mirror"); NSApp.activate(ignoringOtherApps: true)
                link.sendMessage(["t": "mirror_start"])
            }
            ActionTile(icon: "phone.arrow.up.right", label: "Call/text", enabled: connected, active: showDial) { showDial.toggle() }
            ActionTile(icon: "qrcode", label: "Pair", enabled: true) { openPairing() }
        }
    }

    private var dialForm: some View {
        VStack(spacing: 8) {
            TextField("Phone number", text: $number)
            TextField("Message (optional)", text: $message)
            HStack {
                Button("Call") { link.sendMessage(["t": "dial", "number": number]) }.disabled(number.isEmpty)
                Button("Send text") { link.sendMessage(["t": "sms_send", "to": number, "text": message]); message = "" }
                    .disabled(number.isEmpty || message.isEmpty)
                Spacer()
            }
        }.textFieldStyle(.roundedBorder).padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            if link.activity.isEmpty {
                Text("Copy something, share a file or get a notification — it shows up here.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(link.activity.suffix(5).reversed()) { e in
                HStack(spacing: 8) {
                    Image(systemName: e.icon).foregroundStyle(.secondary).frame(width: 18)
                    Text(e.text).font(.callout).lineLimit(1)
                    Spacer()
                    Text(e.time, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }))
                .toggleStyle(.switch).controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.font(.caption)
    }

    private func openPairing() { openWindow(id: "welcome"); NSApp.activate(ignoringOtherApps: true) }
}

struct ActionTile: View {
    let icon: String, label: String, enabled: Bool
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(active ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Pairing window

struct WelcomeView: View {
    @ObservedObject var link: Link
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 42)).foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(link.connectedName == nil ? "Pair your Android phone" : "You're connected").font(.largeTitle.bold())
                Text(link.connectedName == nil ? "Scan once. It reconnects by itself from then on." : "Paired with \(link.connectedName ?? "")")
                    .foregroundStyle(.secondary)
            }
            if link.connectedName == nil {
                if let qr = link.qr {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 220, height: 220)
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                } else { ProgressView().frame(width: 220, height: 220) }
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Install and open Splurter on your phone")
                    step(2, "Tap “Scan QR code”")
                    step(3, "Point the camera at this code")
                }
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                Text("Notifications, clipboard, files, calls and texts are ready.").font(.callout).foregroundStyle(.secondary)
                Button("Done") { dismissWindow(id: "welcome") }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(36).frame(width: 440)
        .onAppear { link.pairing = true; NSApp.activate(ignoringOtherApps: true) }
        .onDisappear { link.pairing = false }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20).background(.tint, in: Circle())
            Text(text).font(.callout)
        }
    }
}
