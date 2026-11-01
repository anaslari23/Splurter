import SwiftUI

/// One-time setup for call audio: find adb, pair the phone's wireless debugging, confirm the connection.
final class SetupModel: ObservableObject {
    @Published var adbPath: String?
    @Published var pairing: Adb.Endpoint?   // the phone's "Pair device with pairing code" dialog, when it's open
    @Published var serial: String?          // an online wireless-debugging connection to the phone
    @Published var code = ""
    @Published var message = ""
    @Published var busy = false
    private var timer: Timer?

    func start() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.refresh() } }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        DispatchQueue.global().async {
            let adb = Adb.shared; let path = adb.path
            var serial: String?; var pairing: Adb.Endpoint?
            if path != nil {
                serial = adb.onlineSerials().first
                let svc = adb.services()
                pairing = svc.pairing.first
                if serial == nil, let c = svc.connect.first(where: { $0.host == Link.shared.phoneHost }) ?? svc.connect.first, adb.connect(c) { serial = adb.onlineSerials().first }
            }
            DispatchQueue.main.async { self.adbPath = path; self.pairing = pairing; self.serial = serial }
        }
    }

    func pair() {
        guard let e = pairing, code.count == 6 else { return }
        busy = true; message = "Pairing…"
        DispatchQueue.global().async {
            let r = Adb.shared.pair(e, code: self.code)
            DispatchQueue.main.async { self.busy = false; self.message = r.ok ? "Paired." : "That didn't work: \(r.message.prefix(100)). The code expires quickly, so try a fresh one."; if r.ok { self.code = "" }; self.refresh() }
        }
    }

    func download() {
        busy = true; message = "Downloading Google's platform-tools…"
        Task { do { try await Adb.shared.downloadPlatformTools(); await MainActor.run { self.busy = false; self.message = "Installed."; self.refresh() } }
               catch { await MainActor.run { self.busy = false; self.message = "Download failed: \(error.localizedDescription)" } } }
    }
}

struct CallAudioSetupView: View {
    @StateObject private var m = SetupModel()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up call audio").font(.title.bold())
            Text("Talk on phone calls through your Mac. This uses Android's wireless debugging once, so there is nothing to buy and nothing is installed on your phone. Use headphones on the Mac to avoid echo.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            step(1, "adb on this Mac", done: m.adbPath != nil) {
                if let p = m.adbPath { Text("Found: \(p)").font(.caption).foregroundStyle(.secondary) }
                else {
                    Text("Splurter drives Android's adb tool. It wasn't found on this Mac.").font(.callout)
                    Button("Download Google's platform-tools (about 13 MB)") { m.download() }.disabled(m.busy)
                }
            }
            step(2, "Pair your phone", done: m.serial != nil) {
                if let s = m.serial { Text("Connected to \(s)").font(.caption).foregroundStyle(.secondary) }
                else if m.adbPath != nil {
                    Text("On the phone: Settings, Developer options, turn on **Wireless debugging**, then tap **Pair device with pairing code**. (No Developer options? Tap Build number 7 times in About phone.)")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let e = m.pairing {
                        Label("Pairing dialog found (\(e.hostPort))", systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
                        HStack { TextField("6-digit code", text: $m.code).frame(width: 120).textFieldStyle(.roundedBorder)
                            Button("Pair") { m.pair() }.disabled(m.code.count != 6 || m.busy) }
                    } else { Label("Waiting for the pairing dialog on your phone…", systemImage: "hourglass").foregroundStyle(.secondary).font(.callout) }
                } else { Text("Finish step 1 first.").font(.callout).foregroundStyle(.secondary) }
            }
            step(3, "Ready", done: m.serial != nil) {
                Text(m.serial != nil ? "During a call, press **Use Mac audio** in the Splurter menu." : "Pair first.").font(.callout)
            }
            if !m.message.isEmpty { Text(m.message).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(m.serial != nil ? "Done" : "Close") { dismissWindow(id: "callaudio") }.keyboardShortcut(.defaultAction) }
        }
        .padding(28).frame(width: 520)
        .onAppear { m.start(); NSApp.activate(ignoringOtherApps: true) }
        .onDisappear { m.stop() }
    }

    @ViewBuilder
    private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle").font(.title2).foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); content() }
        }
    }
}
