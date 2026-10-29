// Draws the README demo (docs/demo.gif) and the link preview image (docs/social.png).
// Everything is drawn here rather than recorded, so the art never shows anyone's real desktop. The
// keyboard is a drawing, the words typed are made up, and the panel is the off-screen render the
// tests save (run `SCREENSHOT_DIR=docs swift test --filter Window` first).
//
//   swift scripts/make-art.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Cool silver light on a dark wallpaper, like the other apps' art.
func wallpaper(_ rect: NSRect) {
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), ending: ink)!.draw(in: rect, angle: -90)
    let glows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.18, 0.75, 0.42, NSColor(srgbRed: 0.84, green: 0.89, blue: 0.95, alpha: 0.45)),
        (0.85, 0.72, 0.38, NSColor(srgbRed: 0.59, green: 0.68, blue: 0.81, alpha: 0.40)),
        (0.70, 0.12, 0.46, NSColor(srgbRed: 0.75, green: 0.81, blue: 0.89, alpha: 0.32)),
        (0.22, 0.15, 0.30, NSColor(srgbRed: 0.44, green: 0.53, blue: 0.65, alpha: 0.32)),
    ]
    for (x, y, r, color) in glows {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * r, options: [])
    }
}

@discardableResult
func text(
    _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
    centered: Bool = false, mono: Bool = false
) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
    return width
}


let width: CGFloat = 720
let height: CGFloat = 450
let board = NSRect(x: 26, y: 60, width: 380, height: 150)
let rows: [[(String, CGFloat)]] = [
    "QWERTYUIOP".map { (String($0), 1) },
    "ASDFGHJKL".map { (String($0), 1) },
    [("⇧", 1.5)] + "ZXCVBNM".map { (String($0), 1) } + [("⏎", 1.5)],
    [("", 6)],
]

func keyRects() -> [(String, NSRect)] {
    var result: [(String, NSRect)] = []
    let unit: CGFloat = 34, gap: CGFloat = 4
    for (r, row) in rows.enumerated() {
        let total = row.reduce(0) { $0 + $1.1 * unit + gap } - gap
        var x = board.midX - total / 2
        let y = board.maxY - 14 - CGFloat(r + 1) * (unit + gap)
        for (label, w) in row {
            result.append((label.isEmpty ? " " : label, NSRect(x: x, y: y, width: w * unit, height: unit)))
            x += w * unit + gap
        }
    }
    return result
}

func keyboard(pressed: String?) {
    let body = NSBezierPath(roundedRect: board, xRadius: 18, yRadius: 18)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    body.stroke()
    for (label, rect) in keyRects() {
        let down = label == pressed
        let cap = rect.offsetBy(dx: 0, dy: down ? -2 : 0)
        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -3), xRadius: 7, yRadius: 7).fill()
        (down ? ice.withAlphaComponent(0.9) : NSColor(srgbRed: 0.86, green: 0.89, blue: 0.94, alpha: 1)).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 7, yRadius: 7).fill()
        text(label, at: NSPoint(x: cap.midX, y: cap.midY - 7), size: 12, weight: .semibold, color: ink.withAlphaComponent(0.75), centered: true)
    }
}

/// Rings coming off a pressed key.
func rings(from label: String, age: CGFloat) {
    guard let rect = keyRects().first(where: { $0.0 == label })?.1 else { return }
    for i in 0..<3 {
        let radius = 26 + age * 26 + CGFloat(i) * 16
        let ring = NSBezierPath(ovalIn: NSRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = 2
        ice.withAlphaComponent(max(0, 0.55 - age * 0.35 - CGFloat(i) * 0.15)).setStroke()
        ring.stroke()
    }
}

/// A sketch of the sound's waveform: a decaying ring, slow and round for a thock, fast for a clack.
func wave(_ rect: NSRect, cycles: CGFloat, decay: CGFloat, amount: CGFloat) {
    NSColor.black.withAlphaComponent(0.3).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
    let path = NSBezierPath()
    for i in 0...200 {
        let t = CGFloat(i) / 200
        let envelope = t < 0.06 ? t / 0.06 : exp(-(t - 0.06) * decay)
        let y = rect.midY + sin(t * cycles * 2 * .pi) * envelope * amount * rect.height * 0.42
        let point = NSPoint(x: rect.minX + 12 + t * (rect.width - 24), y: y)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.lineWidth = 1.6
    ice.setStroke()
    path.stroke()
}

let shots = ["Deep thock": NSImage(contentsOfFile: "docs/screenshot-board.png")!, "Bright clack": NSImage(contentsOfFile: "docs/screenshot-clack.png")!]
let panelRect = NSRect(x: 430, y: 26, width: 264, height: 264 * 912 / 680)

func scene(preset: String, typed: String, pressed: String?, age: CGFloat) -> NSBitmapImageRep {
    bitmap(Int(width), Int(height)) {
        wallpaper(NSRect(x: 0, y: 0, width: width, height: height))
        let thock = preset == "Deep thock"
        text(preset.uppercased(), at: NSPoint(x: 30, y: height - 52), size: 12, weight: .semibold, color: ice, mono: true)
        text("Design your keyboard's sound", at: NSPoint(x: 30, y: height - 84), size: 22, weight: .semibold)
        let field = NSRect(x: 26, y: 236, width: 380, height: 46)
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: field, xRadius: 12, yRadius: 12).fill()
        text(typed + "▍", at: NSPoint(x: field.minX + 14, y: field.minY + 13), size: 16, color: .white.withAlphaComponent(0.9))
        wave(NSRect(x: 26, y: 296, width: 380, height: 58), cycles: thock ? 5 : 16, decay: thock ? 9 : 5, amount: pressed == nil ? 0.15 : 1)
        keyboard(pressed: pressed)
        if let pressed { rings(from: pressed, age: age) }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        shots[preset]!.draw(in: panelRect)
        NSGraphicsContext.restoreGraphicsState()
        text("made from numbers · no recordings", at: NSPoint(x: 30, y: 24), size: 11, color: .white.withAlphaComponent(0.45), mono: true)
    }
}

var frames: [(NSBitmapImageRep, Double)] = []
for (preset, word) in [("Deep thock", "lab notes"), ("Bright clack", "lab notes")] {
    frames.append((scene(preset: preset, typed: "", pressed: nil, age: 0), 1.0))
    var typed = ""
    for ch in word {
        let label = ch == " " ? " " : String(ch).uppercased()
        typed.append(ch)
        frames.append((scene(preset: preset, typed: typed, pressed: label, age: 0), 0.08))
        frames.append((scene(preset: preset, typed: typed, pressed: label, age: 1), 0.1))
        frames.append((scene(preset: preset, typed: typed, pressed: nil, age: 0), 0.06))
    }
    frames.append((scene(preset: preset, typed: typed, pressed: nil, age: 0), 1.4))
}

let gifURL = URL(fileURLWithPath: "docs/demo.gif")
let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (rep, hold) in frames {
    CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write the GIF") }

let social = bitmap(1280, 640) {
    wallpaper(NSRect(x: 0, y: 0, width: 1280, height: 640))
    NSImage(contentsOfFile: "docs/icon.png")!.draw(in: NSRect(x: 96, y: 372, width: 150, height: 150))
    text("Tonecap", at: NSPoint(x: 96, y: 262), size: 84, weight: .semibold)
    text("Design your keyboard's sound.", at: NSPoint(x: 100, y: 200), size: 36, color: .white.withAlphaComponent(0.85))
    text("Made from numbers, not recordings. Free and open source.", at: NSPoint(x: 100, y: 150), size: 22, color: .white.withAlphaComponent(0.6))
    wave(NSRect(x: 100, y: 64, width: 560, height: 60), cycles: 7, decay: 7, amount: 1)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    shots["Deep thock"]!.draw(in: NSRect(x: 820, y: 40, width: 420, height: 420 * 912 / 680))
    NSGraphicsContext.restoreGraphicsState()
}
try social.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
Swift.print("Wrote docs/demo.gif and docs/social.png")
