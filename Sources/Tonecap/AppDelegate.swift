import AppKit
import ServiceManagement
import SwiftUI
import ToneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let hotkey = Hotkey()
    private let player = Player()
    private lazy var model = Model(player: player)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        updateIcon()

        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: PanelView(
            model: model,
            allow: { [unowned self] in allow() },
            openSite: { [unowned self] in Links.openPlayground(model.settings.design); popover.performClose(nil) },
            copyLink: { [unowned self] in Links.copy(model.settings.design) },
            quit: { NSApp.terminate(nil) },
            loginItem: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
                if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            })
        ))

        hotkey.onPress = { [weak self] in
            self?.model.toggleMute()
            self?.updateIcon()
        }
        hotkey.register()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.model.frontAppChanged(id: app?.bundleIdentifier, name: app?.localizedName) }
        }
        let front = NSWorkspace.shared.frontmostApplication
        model.frontAppChanged(id: front?.bundleIdentifier, name: front?.localizedName)
        player.onDeviceChange = { [weak self] in
            guard let self, self.player.refreshFormat() else { return }
            self.model.renderSounds()
        }

        model.renderSounds()
        model.refreshAccess()
        if !model.hasAccess { togglePanel() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.refreshAccess()
                self.player.stopIfIdle()
                self.updateIcon()
            }
        }
    }

    private func allow() {
        KeyListener.ask()
        Links.openSettings()
    }

    private func updateIcon() {
        statusItem.button?.image = StatusIcon.image(muted: model.muted || !model.isListening)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshAccess()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        updateIcon()
    }
}
