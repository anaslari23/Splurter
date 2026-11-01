// Generates the Splurter app icon: icons/AppIcon.icns (Mac) and the Android adaptive-icon foreground PNG.
// Run: swift icons/make_icons.swift   (from native/)
import AppKit

let top = NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1), bottom = NSColor(red: 0.13, green: 0.62, blue: 1.0, alpha: 1)

func glyph(_ px: CGFloat) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: px, weight: .semibold)
    let sym = NSImage(systemSymbolName: "iphone.radiowaves.left.and.right", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let out = NSImage(size: sym.size)
    out.lockFocus()
    sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set(); NSRect(origin: .zero, size: sym.size).fill(using: .sourceIn) // tint white
    out.unlockFocus()
    return out
}

func png(_ size: Int, _ draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawGlyph(in r: CGRect, scale: CGFloat) {
    let g = glyph(r.width * scale)
    g.draw(in: CGRect(x: r.midX - g.size.width / 2, y: r.midY - g.size.height / 2, width: g.size.width, height: g.size.height))
}

// Mac: Big Sur squircle with the standard ~10% margin.
func macIcon(_ s: Int) -> Data {
    png(s) { r in
        let body = r.insetBy(dx: r.width * 0.098, dy: r.height * 0.098)
        let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = r.width * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -r.width * 0.01); shadow.set()
        NSColor.black.set(); path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -60)
        drawGlyph(in: body, scale: 0.44)
    }
}

let fm = FileManager.default
let iconset = "icons/AppIcon.iconset"
try? fm.removeItem(atPath: iconset); try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! macIcon(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name.replacingOccurrences(of: "@2x", with: "")  == name ? "\(name)x\(name)" : "\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))@2x").png"))
}
let p = Process(); p.launchPath = "/usr/bin/iconutil"; p.arguments = ["-c", "icns", iconset, "-o", "icons/AppIcon.icns"]; try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)

// Android adaptive icon foreground: 432 px = 108 dp @ xxxhdpi, glyph kept inside the 66% safe zone.
let fg = png(432) { r in drawGlyph(in: r, scale: 0.30) }
let dir = "android/app/src/main/res/mipmap-xxxhdpi"; try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
try! fg.write(to: URL(fileURLWithPath: "\(dir)/ic_launcher_foreground.png"))
print("done")
