@preconcurrency import AVFoundation
import AudioToolbox
import os
import ToneCore

/// Plays the sounds. Every sound is rendered ahead of time into a buffer, and a pool of players is
/// kept running, so a key press only hands a buffer to the next player: no rendering, no file and
/// no allocation on the way to the speakers.
final class Player: @unchecked Sendable {
    static let voices = 12
    /// Frames per audio cycle asked of the output device: about 2.7 ms at 48 kHz.
    static let ioFrames: UInt32 = 128
    /// The audio engine stops after this long without a key, so it isn't holding the speakers awake.
    static let idleStop: TimeInterval = 120

    let engine = AVAudioEngine()
    let offline: Bool
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [[[AVAudioPCMBuffer]]] = []
    private var format: AVAudioFormat
    private var nextVoice = 0
    private var picker = VariantPicker(seed: UInt32.random(in: 1...UInt32.max))
    private let lock = OSAllocatedUnfairLock()
    private var lastPlay = Date.distantPast
    /// Starting the audio engine takes a moment, so it's done here, never on the key thread.
    private let starter = DispatchQueue(label: "Tonecap audio start")
    private var starting = false
    private var lastFailure = Date.distantPast

    /// `offline` renders into memory instead of the speakers, for tests.
    init(offline: Bool = false) {
        self.offline = offline
        let rate = offline ? 48000 : engine.outputNode.outputFormat(forBus: 0).sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48000, channels: 1)!
        if offline {
            try? engine.enableManualRenderingMode(.offline, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!, maximumFrameCount: 4096)
        }
        for _ in 0..<Player.voices {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
        }
        if !offline { NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged), name: .AVAudioEngineConfigurationChange, object: engine) }
    }

    var sampleRate: Double { format.sampleRate }

    /// Swaps in a new set of sounds. Keys pressed meanwhile keep using the old ones.
    func load(_ bank: SoundBank) {
        let loaded = bank.sounds.map { variants in
            variants.map { pair in
                pair.map { samples -> AVAudioPCMBuffer in
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
                    buffer.frameLength = AVAudioFrameCount(samples.count)
                    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                    return buffer
                }
            }
        }
        lock.withLockUnchecked { buffers = loaded }
    }

    func start() throws {
        guard !engine.isRunning else { return }
        if !offline, let unit = engine.outputNode.audioUnit {
            var frames = Player.ioFrames
            AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, UInt32(MemoryLayout<UInt32>.size))
        }
        engine.prepare()
        try engine.start()
        for node in nodes { node.play() }
    }

    func stop() {
        engine.stop()
    }

    /// Plays one stroke on the next free voice. Safe from any thread. If the engine was stopped
    /// for being idle, it's started on another queue and the stroke plays once it's running.
    func play(_ stroke: Stroke, volume: Float) {
        let running = lock.withLock { () -> Bool in
            if engine.isRunning { return true }
            // After a failure (no output device, say), wait a few seconds before trying again.
            guard !starting, Date().timeIntervalSince(lastFailure) > 5 else { return false }
            starting = true
            return false
        }
        if running {
            schedule(stroke, volume: volume)
            return
        }
        starter.async { [self] in
            let ok = lock.withLock { () -> Bool in
                defer { starting = false }
                do { try start() } catch { lastFailure = Date() }
                return engine.isRunning
            }
            if ok { schedule(stroke, volume: volume) }
        }
    }

    private func schedule(_ stroke: Stroke, volume: Float) {
        lock.withLock {
            guard !buffers.isEmpty, engine.isRunning else { return }
            let variant = picker.next(widthIndex: stroke.widthIndex, count: buffers[stroke.widthIndex].count)
            let buffer = buffers[stroke.widthIndex][variant][stroke.up ? 1 : 0]
            let node = nodes[nextVoice]
            nextVoice = (nextVoice + 1) % nodes.count
            node.pan = Float(stroke.pan)
            node.volume = volume
            // Stopping first clears whatever this voice played last and restarts its clock, so the
            // new buffer starts on the next audio cycle.
            node.stop()
            node.scheduleBuffer(buffer, at: nil)
            node.play()
            lastPlay = Date()
        }
    }

    /// Stops the engine if no key has played for a while. Called now and then from the main thread.
    func stopIfIdle(now: Date = Date()) {
        lock.withLock {
            if engine.isRunning, now.timeIntervalSince(lastPlay) > Player.idleStop { engine.stop() }
        }
    }

    /// The output device changed (headphones plugged in, say): the engine stopped, so start it
    /// again when it's next needed.
    @objc private func configurationChanged() {
        // Never under the lock here: AVAudioEngine may post this while starting, on the thread that holds it.
        starter.async { [self] in lock.withLock { engine.stop() } }
        let changed = onDeviceChange
        DispatchQueue.main.async { MainActor.assumeIsolated { changed?() } }
    }

    /// Called on the main thread after the output device changed.
    var onDeviceChange: (@MainActor @Sendable () -> Void)?

    /// A new device can run at a different rate, so the sounds must be rendered again for it.
    func refreshFormat() -> Bool {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard !offline, rate > 0, rate != format.sampleRate else { return false }
        lock.withLock {
            engine.stop()
            format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            for node in nodes { engine.disconnectNodeOutput(node); engine.connect(node, to: engine.mainMixerNode, format: format) }
            buffers = []
        }
        return true
    }
}
