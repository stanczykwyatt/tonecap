import AppKit
import ToneCore

/// The only things Tonecap opens or copies: the Input Monitoring page in System Settings, the
/// playground with the current sound, and that same link on the clipboard.
@MainActor
enum Links {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Opens the playground in the browser. The sound travels after the `#`, which browsers never send to a server.
    static func openPlayground(_ design: Design) {
        guard let url = URL(string: ShareCode.link(design)), url.host == "stanczykwyatt.github.io" else { return }
        NSWorkspace.shared.open(url)
    }

    static func copy(_ design: Design) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ShareCode.link(design), forType: .string)
    }
}
