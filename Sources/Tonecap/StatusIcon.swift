import AppKit

/// The menu bar icon: a keycap with a sound wave, and a slash through it while muted.
enum StatusIcon {
    static func image(muted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let cap = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 10, height: 10), xRadius: 2.6, yRadius: 2.6)
            cap.lineWidth = 1.6
            cap.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 6, width: 5, height: 4), xRadius: 1.2, yRadius: 1.2).fill()
            for (radius, alpha) in [(3.2, 1.0), (5.6, 0.7)] {
                let wave = NSBezierPath()
                wave.appendArc(withCenter: NSPoint(x: 11.5, y: 9.5), radius: radius, startAngle: -40, endAngle: 40)
                wave.lineWidth = 1.4
                wave.lineCapStyle = .round
                NSColor.black.withAlphaComponent(muted ? 0.35 : alpha).setStroke()
                wave.stroke()
            }
            if muted {
                NSColor.black.setStroke()
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2, y: 16))
                slash.line(to: NSPoint(x: 16, y: 2))
                slash.lineWidth = 1.6
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = muted ? "Tonecap, muted" : "Tonecap"
        return image
    }
}
