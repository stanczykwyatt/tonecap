@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Tonecap
import ToneCore

/// The player, through an audio engine that renders into memory: nothing reaches the speakers.
/// One engine at a time: offline engines running side by side in one process interfere.
@Suite(.serialized) struct PlayerTests {
    func render(_ player: Player, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: player.engine.manualRenderingFormat, frameCapacity: frames)!
        let status = try player.engine.renderOffline(frames, to: buffer)
        #expect(status == .success)
        return buffer
    }

    func energy(_ buffer: AVAudioPCMBuffer, channel: Int, from: Int = 0, to: Int? = nil) -> Float {
        let data = buffer.floatChannelData![channel]
        return (from..<(to ?? Int(buffer.frameLength))).reduce(0) { $0 + data[$1] * data[$1] }
    }

    func readyPlayer() throws -> Player {
        let player = Player(offline: true)
        player.load(SoundBank(design: Design.presets[1].design, sampleRate: player.sampleRate, variants: 2))
        try player.start()
        return player
    }

    @Test func aStrokeSoundsWithinOneCycle() throws {
        let player = try readyPlayer()
        _ = try render(player, frames: 128)
        let key = Keyboard.sound(for: 0)
        player.play(Stroke(keyCode: 0, widthIndex: key.widthIndex, pan: key.pan, up: false), volume: 1)
        // The graph takes the buffer at the start of the next cycle: at the app's 128 frames a
        // cycle, that's under 3 ms at 48 kHz, before the output device's own delay.
        let first = try render(player, frames: 128), second = try render(player, frames: 128)
        #expect(energy(first, channel: 0) + energy(second, channel: 0) > 0)
        let rest = try render(player, frames: 4096)
        #expect(energy(rest, channel: 0) > 0)
        player.stop()
    }

    @Test func silenceUntilAKeyPlays() throws {
        let player = try readyPlayer()
        let quiet = try render(player, frames: 2048)
        #expect(energy(quiet, channel: 0) == 0 && energy(quiet, channel: 1) == 0)
        player.stop()
    }

    @Test func keysArePannedByPosition() throws {
        for (keyCode, leftLouder) in [(UInt16(12), true), (UInt16(124), false)] {
            let player = try readyPlayer()
            let key = Keyboard.sound(for: keyCode)
            player.play(Stroke(keyCode: keyCode, widthIndex: key.widthIndex, pan: key.pan, up: false), volume: 1)
            let out = try render(player, frames: 4096)
            #expect((energy(out, channel: 0) > energy(out, channel: 1)) == leftLouder)
            player.stop()
        }
    }

    @Test func volumeScales() throws {
        var levels: [Float] = []
        for volume in [Float(1), 0.25] {
            let player = try readyPlayer()
            player.play(Stroke(keyCode: 49, widthIndex: 7, pan: 0, up: false), volume: volume)
            levels.append(energy(try render(player, frames: 4096), channel: 0))
            player.stop()
        }
        #expect(levels[1] < levels[0] / 10)
    }

    @Test func manyFastStrokesDontPileUp() throws {
        let player = try readyPlayer()
        for i in 0..<50 { player.play(Stroke(keyCode: 0, widthIndex: 0, pan: 0, up: i % 2 == 1), volume: 1) }
        let out = try render(player, frames: 4096)
        let data = out.floatChannelData![0]
        #expect((0..<Int(out.frameLength)).allSatisfy { data[$0].isFinite && abs(data[$0]) < 12 })
        player.stop()
    }

    @MainActor @Test func theModelRendersSoundsOffTheMainThread() async throws {
        let player = Player(offline: true)
        let m = Model(store: .memory(), player: player, access: { true })
        m.renderSounds()
        #expect(m.isRendering)
        await m.finishRendering()
        #expect(!m.isRendering)
        try player.start()
        player.play(Stroke(keyCode: 0, widthIndex: 0, pan: 0, up: false), volume: 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: player.engine.manualRenderingFormat, frameCapacity: 2048)!
        _ = try player.engine.renderOffline(2048, to: buffer)
        #expect((0..<2048).contains { buffer.floatChannelData![0][$0] != 0 })
        player.stop()
    }

    @Test func nothingPlaysBeforeSoundsLoad() throws {
        let player = Player(offline: true)
        try player.start()
        player.play(Stroke(keyCode: 0, widthIndex: 0, pan: 0, up: false), volume: 1)
        #expect(energy(try render(player, frames: 1024), channel: 0) == 0)
        player.stop()
    }
}

@MainActor
@Suite struct ModelTests {
    func model() -> Model { Model(store: .memory(), player: nil, access: { true }) }

    @Test func editsArePersisted() {
        let store = SettingsStore.memory()
        let a = Model(store: store, access: { true })
        a.edit { $0.foam = 12 }
        a.volume = 0.25
        let b = Model(store: store, access: { true })
        #expect(b.settings.design.foam == 12 && b.settings.volume == 0.25 && b.settings.designName == nil)
    }

    @Test func presetsAndImport() {
        let m = model()
        m.choose(Design.presets[4])
        #expect(m.settings.designName == "Heavy brass")
        m.importDesign("nonsense")
        #expect(m.importMessage == "That isn't a Tonecap link or code.")
        m.importDesign(ShareCode.link(Design.presets[2].design))
        #expect(m.settings.design == Design.presets[2].design)
        #expect(m.importMessage == "Imported Crisp click.")
        #expect(m.shareLink.hasPrefix("https://stanczykwyatt.github.io/tonecap/#s="))
    }

    @Test func theKeyThreadFollowsMuteAndFrontApp() {
        let m = model()
        let down = KeyEvent.down(keyCode: 0, isRepeat: false)
        let up = KeyEvent.up(keyCode: 0)
        m.frontAppChanged(id: "com.example.Notes", name: "Notes")
        #expect(m.snapshot.stroke(for: down) != nil)
        #expect(m.snapshot.stroke(for: up)?.0.up == true)
        m.setMuted("com.example.Notes", true)
        #expect(m.snapshot.stroke(for: down) == nil)
        m.frontAppChanged(id: "com.example.Mail", name: "Mail")
        #expect(m.snapshot.stroke(for: down)?.1 == Float(m.volume))
        m.toggleMute()
        #expect(m.snapshot.stroke(for: down) == nil)
        m.toggleMute()
        m.playsReleases = false
        _ = m.snapshot.stroke(for: .down(keyCode: 5, isRepeat: false))
        #expect(m.snapshot.stroke(for: .up(keyCode: 5)) == nil)
    }

    @Test func remembersTheLastAppThatWasntItself() {
        let m = model()
        m.frontAppChanged(id: "com.example.Notes", name: "Notes\u{202E}")
        m.frontAppChanged(id: Bundle.main.bundleIdentifier, name: "Tonecap")
        #expect(m.frontApp?.id == "com.example.Notes" && m.frontApp?.name == "Notes")
    }

    @Test func withoutAccessItDoesntListen() {
        let m = Model(store: .memory(), access: { false })
        m.refreshAccess()
        #expect(!m.hasAccess && !m.isListening)
    }
}

@Suite struct ListenerTests {
    @Test func eventsCarryOnlyKeyCodesAndFlags() {
        #expect(KeyListener.keyEvent(type: .keyDown, keyCode: 4, isRepeat: true, flags: 0) == .down(keyCode: 4, isRepeat: true))
        #expect(KeyListener.keyEvent(type: .keyUp, keyCode: 4, isRepeat: false, flags: 0) == .up(keyCode: 4))
        #expect(KeyListener.keyEvent(type: .flagsChanged, keyCode: 56, isRepeat: false, flags: 0x20000) == .flagsChanged(keyCode: 56, flags: 0x20000))
    }
}

@Suite struct BundleTests {
    nonisolated(unsafe) static let plist: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Info.plist")
        return try! PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
    }()

    @Test func isAMenuBarApp() {
        #expect(Self.plist["LSUIElement"] as? Bool == true)
        #expect(Self.plist["CFBundleIdentifier"] as? String == "com.stanczykwyatt.Tonecap")
        #expect(Self.plist["CFBundleExecutable"] as? String == "Tonecap")
    }

    @Test func asksForNothingElse() {
        for key in ["NSAppleEventsUsageDescription", "NSMicrophoneUsageDescription", "NSCameraUsageDescription", "NSAppTransportSecurity", "CFBundleURLTypes"] {
            #expect(Self.plist[key] == nil, "\(key)")
        }
    }
}
