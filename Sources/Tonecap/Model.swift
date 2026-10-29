import AppKit
import AVFoundation
import Observation
import os
import ToneCore

/// Where settings are kept. The app uses UserDefaults; tests use memory.
struct SettingsStore: Sendable {
    var load: @Sendable () -> Data?
    var save: @Sendable (Data) -> Void

    static let standard = SettingsStore(
        load: { UserDefaults.standard.data(forKey: "settings") },
        save: { UserDefaults.standard.set($0, forKey: "settings") }
    )

    static func memory() -> SettingsStore {
        let box = OSAllocatedUnfairLock<Data?>(initialState: nil)
        return SettingsStore(load: { box.withLock { $0 } }, save: { data in box.withLock { $0 = data } })
    }
}

/// What the key thread needs to decide, without waiting for the main thread.
final class Snapshot: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var settings = Settings()
    private var frontApp: String?
    private var tracker = KeyTracker()

    func update(settings: Settings? = nil, frontApp: String?? = nil) {
        lock.withLock {
            if let settings {
                self.settings = settings
                tracker.playsRepeats = settings.playsRepeats
            }
            if let frontApp { self.frontApp = frontApp }
        }
    }

    /// The stroke to play for a key event and its volume, or nil for silence.
    func stroke(for event: KeyEvent) -> (Stroke, Float)? {
        lock.withLock {
            guard let stroke = tracker.handle(event), settings.plays(stroke, frontApp: frontApp) else { return nil }
            return (stroke, Float(settings.volume))
        }
    }

    func reset() { lock.withLock { tracker.reset() } }
}

@MainActor
@Observable
final class Model {
    private(set) var settings: Settings
    private(set) var hasAccess: Bool
    private(set) var isListening = false
    /// The last app in front other than Tonecap, which the panel offers to mute.
    private(set) var frontApp: (id: String, name: String)?
    private(set) var isRendering = false
    var importMessage: String?

    @ObservationIgnored let snapshot = Snapshot()
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored let player: Player?
    @ObservationIgnored private let access: () -> Bool
    @ObservationIgnored private var listener: KeyListener?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored var appName: @MainActor (String) -> String = { Model.liveAppName($0) }

    init(store: SettingsStore = .standard, player: Player? = nil, access: @escaping () -> Bool = { KeyListener.hasAccess }) {
        self.store = store
        self.player = player
        self.access = access
        settings = Settings.load(store.load())
        hasAccess = access()
        snapshot.update(settings: settings)
    }

    // MARK: Settings

    private func changed(rebuild: Bool = false) {
        store.save(settings.data())
        snapshot.update(settings: settings)
        if rebuild { renderSounds() }
    }

    func edit(_ change: @escaping (inout Design) -> Void) {
        let before = settings.design
        settings.edit(change)
        changed(rebuild: settings.design != before)
    }

    func choose(_ preset: Preset) {
        settings.choose(preset)
        changed(rebuild: true)
    }

    func importDesign(_ text: String) {
        if settings.importDesign(text) {
            importMessage = "Imported \(settings.designName ?? "a custom sound")."
            changed(rebuild: true)
        } else {
            importMessage = "That isn't a Tonecap link or code."
        }
    }

    var shareLink: String { ShareCode.link(settings.design) }

    var volume: Double {
        get { settings.volume }
        set { settings.volume = min(1, max(0, newValue)); changed() }
    }

    var muted: Bool {
        get { settings.muted }
        set { settings.muted = newValue; changed() }
    }

    var playsReleases: Bool {
        get { settings.playsReleases }
        set { settings.playsReleases = newValue; changed() }
    }

    var playsRepeats: Bool {
        get { settings.playsRepeats }
        set { settings.playsRepeats = newValue; changed() }
    }

    func toggleMute() { muted.toggle() }

    func setMuted(_ app: String, _ isMuted: Bool) {
        settings.setMuted(app, isMuted)
        changed()
    }

    func isMuted(_ app: String) -> Bool { settings.mutedApps.contains(app) }

    // MARK: Apps

    func frontAppChanged(id: String?, name: String?) {
        snapshot.update(frontApp: .some(id))
        if let id, id != Bundle.main.bundleIdentifier {
            frontApp = (id, name.map(Settings.cleanName) ?? id)
        }
    }

    static func liveAppName(_ id: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, let name = app.localizedName {
            return Settings.cleanName(name)
        }
        return id
    }

    // MARK: Listening and sound

    /// Checks Input Monitoring and the tap. Called when the panel opens and every couple of seconds:
    /// if the permission was turned off, it stops; if it came back, or macOS dropped the tap, it starts again.
    func refreshAccess() {
        hasAccess = access()
        if !hasAccess {
            if isListening { stopListening() }
            return
        }
        if isListening, listener?.isRunning == false { stopListening() }
        if !isListening { startListening() }
    }

    func startListening() {
        guard listener == nil else { return }
        let snapshot = snapshot
        let player = player
        let listener = KeyListener(handler: { event in
            guard let (stroke, volume) = snapshot.stroke(for: event) else { return }
            player?.play(stroke, volume: volume)
        }, reset: { snapshot.reset() })
        if listener.start() {
            self.listener = listener
            isListening = true
        }
    }

    func stopListening() {
        listener?.stop()
        listener = nil
        isListening = false
        snapshot.reset()
    }

    /// Renders every sound for the current design off the main thread, then swaps them in.
    func renderSounds() {
        guard let player else { return }
        renderTask?.cancel()
        let design = settings.design
        let rate = player.sampleRate
        isRendering = true
        renderTask = Task {
            // Dragging a slider changes the design many times a second; only render once it settles.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let bank = await Task.detached(priority: .userInitiated) { SoundBank(design: design, sampleRate: rate) }.value
            guard !Task.isCancelled else { return }
            player.load(bank)
            isRendering = false
        }
    }

    /// Waits for the sounds being rendered, for tests.
    func finishRendering() async { await renderTask?.value }

    /// Plays a short line of typing through the speakers, for the panel's Test button. No keys are
    /// pressed or watched.
    func playTest() {
        guard let player else { return }
        let volume = Float(settings.volume)
        let line: [UInt16] = [17, 4, 14, 49, 8, 31, 1, 49, 35, 0, 46, 14, 36]
        for (index, keyCode) in line.enumerated() {
            let sound = Keyboard.sound(for: keyCode)
            let down = Stroke(keyCode: keyCode, widthIndex: sound.widthIndex, pan: sound.pan, up: false)
            let up = Stroke(keyCode: keyCode, widthIndex: sound.widthIndex, pan: sound.pan, up: true)
            let at = Double(index) * 0.13 + (keyCode == 49 ? 0.05 : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { player.play(down, volume: volume) }
            if settings.playsReleases {
                DispatchQueue.main.asyncAfter(deadline: .now() + at + 0.075) { player.play(up, volume: volume) }
            }
        }
    }
}
