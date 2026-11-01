import SwiftUI

/// Always-on-top incoming-call popup, independent of macOS notification settings (banners vanish after a few seconds
/// or get suppressed by Focus; a ringing phone shouldn't).
final class CallPanel {
    static let shared = CallPanel()
    private var panel: NSPanel?

    func update(_ c: Link.Call?) {
        guard let c, c.state == "ringing" else { panel?.orderOut(nil); panel = nil; return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 92), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .statusBar; p.isFloatingPanel = true; p.hasShadow = true; p.isOpaque = false; p.backgroundColor = .clear
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: CallPanelView(link: Link.shared))
            if let s = NSScreen.main { p.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - 380, y: s.visibleFrame.maxY - 112)) }
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}

struct CallPanelView: View {
    @ObservedObject var link: Link

    var body: some View {
        let c = link.call
        let who = (c?.name.isEmpty == false ? c?.name : c?.number) ?? ""
        HStack(spacing: 12) {
            Image(systemName: "phone.fill").foregroundStyle(.white).frame(width: 40, height: 40).background(.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(who.isEmpty ? "Unknown caller" : who).font(.headline).lineLimit(1)
                Text("Incoming call · Pixel").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { link.sendMessage(["t": "call_end"]) } label: { Image(systemName: "phone.down.fill") }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            Button { link.sendMessage(["t": "call_answer"]) } label: { Image(systemName: "phone.fill") }
                .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
        }
        .padding(14).frame(width: 360, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
    }
}
