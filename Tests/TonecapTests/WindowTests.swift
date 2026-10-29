import AppKit
import SwiftUI
import Testing
@testable import Tonecap
import ToneCore

/// Renders the panel into bitmaps from windows that are never shown, so nothing appears on screen
/// or takes focus. Set SCREENSHOT_DIR to also save the renders as the README screenshots:
///
///   SCREENSHOT_DIR=docs swift test --filter "Window"
@MainActor
@Suite("Window", .serialized)
struct WindowTests {
    func gallery(access: Bool = true) -> Model {
        let m = Model(store: .memory(), access: { access })
        m.appName = { $0 == "com.example.meetings" ? "Huddle" : $0 }
        m.choose(Design.presets[0])
        m.frontAppChanged(id: "com.example.notebook", name: "Notebook")
        m.setMuted("com.example.meetings", true)
        return m
    }

    @Test(arguments: PanelTab.allCases)
    func rendersEachTab(tab: PanelTab) {
        let view = PanelView(model: gallery(), tab: tab)
        let image = render(view, name: "screenshot-\(tab.rawValue.lowercased())")
        #expect(image.pixelsWide >= Int(PanelView.width))
        #expect(colors(in: image) > 12)
    }

    @Test func rendersAnotherPreset() {
        let m = gallery()
        m.choose(Design.presets[1])
        #expect(colors(in: render(PanelView(model: m, tab: .sound), name: "screenshot-clack")) > 12)
    }

    @Test func rendersTheAccessRequest() {
        #expect(colors(in: render(PanelView(model: gallery(access: false)), name: "screenshot-access")) > 8)
    }

    @Test func thePanelHasAFixedWidth() {
        let host = NSHostingView(rootView: PanelView(model: gallery(), tab: .build))
        #expect(host.fittingSize.width == PanelView.width)
        #expect(host.fittingSize.height > 360 && host.fittingSize.height < 640)
    }

    @Test func everySymbolExists() {
        for symbol in ["keyboard", "play.fill", "checkmark"] {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol \(symbol)")
        }
    }

    @Test func theMenuBarIconIsATemplate() {
        for muted in [false, true] {
            let image = StatusIcon.image(muted: muted)
            #expect(image.isTemplate && image.size == NSSize(width: 18, height: 18))
            #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
            #expect(image.accessibilityDescription?.hasPrefix("Tonecap") == true)
        }
    }

    private func render(_ view: some View, name: String?) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        // Never ordered front: it only gives the view a backing to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        if let name, let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
        return image
    }

    private func colors(in image: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: image.pixelsWide, by: 5) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 5) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                seen.insert(UInt32(color.redComponent * 31) << 10 | UInt32(color.greenComponent * 31) << 5 | UInt32(color.blueComponent * 31))
            }
        }
        return seen.count
    }
}
