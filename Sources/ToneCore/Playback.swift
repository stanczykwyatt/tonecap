import Foundation

/// Every sound one design can make, rendered ahead of time so a key press only has to start a buffer.
public struct SoundBank: Sendable {
    public static let variants = 8
    public let design: Design
    public let sampleRate: Double
    /// `sounds[widthIndex][variant][up ? 1 : 0]`
    public let sounds: [[[[Float]]]]

    public init(design: Design, sampleRate: Double, variants: Int = SoundBank.variants) {
        self.design = design
        self.sampleRate = sampleRate
        let gain = Engine.designGain(design, sampleRate: sampleRate)
        sounds = Keyboard.widths.map { width in
            (0..<variants).map { variant in
                [false, true].map { up in
                    Engine.render(design, width: width, variant: variant, up: up, sampleRate: sampleRate, gain: gain)
                }
            }
        }
    }

    public func sound(widthIndex: Int, variant: Int, up: Bool) -> [Float] {
        sounds[widthIndex][variant % sounds[widthIndex].count][up ? 1 : 0]
    }
}

/// Picks which variant plays next for each key size, never the same one twice in a row, so fast
/// typing doesn't sound like a machine gun.
public struct VariantPicker: Sendable {
    var state: UInt32
    var last: [Int: Int] = [:]

    public init(seed: UInt32) { state = seed == 0 ? 1 : seed }

    public mutating func next(widthIndex: Int, count: Int = SoundBank.variants) -> Int {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        var pick = Int(state % UInt32(count))
        if count > 1, pick == last[widthIndex] { pick = (pick + 1) % count }
        last[widthIndex] = pick
        return pick
    }
}

/// What the key-event listener saw. Key codes and modifier flags only; never characters.
public enum KeyEvent: Equatable, Sendable {
    case down(keyCode: UInt16, isRepeat: Bool)
    case up(keyCode: UInt16)
    /// A modifier key changed. `flags` is the event's raw modifier flags.
    case flagsChanged(keyCode: UInt16, flags: UInt64)
}

/// A sound to play.
public struct Stroke: Equatable, Sendable {
    public let keyCode: UInt16
    public let widthIndex: Int
    public let pan: Double
    public let up: Bool

    public init(keyCode: UInt16, widthIndex: Int, pan: Double, up: Bool) {
        self.keyCode = keyCode
        self.widthIndex = widthIndex
        self.pan = pan
        self.up = up
    }
}

/// Turns key events into strokes: skips auto-repeat, works out whether a modifier went down or
/// up, and plays a release only for a key it heard go down.
public struct KeyTracker: Sendable {
    var held: Set<UInt16> = []
    public var playsRepeats = false

    public init() {}

    /// Modifier keys and the flag that's set while either of each pair is held.
    static let modifierFlags: [UInt16: UInt64] = [
        56: 0x20000, 60: 0x20000, // shift
        59: 0x40000, 62: 0x40000, // control
        58: 0x80000, 61: 0x80000, // option
        55: 0x100000, 54: 0x100000, // command
        63: 0x800000, // fn
    ]
    static let capsLock: UInt16 = 57

    public mutating func handle(_ event: KeyEvent) -> Stroke? {
        switch event {
        case let .down(keyCode, isRepeat):
            if isRepeat && !playsRepeats { return nil }
            if held.count >= 64 { held.removeAll() }
            held.insert(keyCode)
            return stroke(keyCode, up: false)
        case let .up(keyCode):
            guard held.remove(keyCode) != nil else { return nil }
            return stroke(keyCode, up: true)
        case let .flagsChanged(keyCode, flags):
            // Caps Lock reports a change when it's pressed, and nothing when it's let go.
            if keyCode == KeyTracker.capsLock { return stroke(keyCode, up: false) }
            guard let mask = KeyTracker.modifierFlags[keyCode] else { return nil }
            if flags & mask == 0 || held.contains(keyCode) {
                // Up if the flag is off, or if this key was already down (the other one of its pair is still held).
                guard held.remove(keyCode) != nil else { return nil }
                return stroke(keyCode, up: true)
            }
            if held.count >= 64 { held.removeAll() }
            held.insert(keyCode)
            return stroke(keyCode, up: false)
        }
    }

    /// Forget held keys, after the listener was paused and may have missed releases.
    public mutating func reset() { held.removeAll() }

    func stroke(_ keyCode: UInt16, up: Bool) -> Stroke {
        let sound = Keyboard.sound(for: keyCode)
        return Stroke(keyCode: keyCode, widthIndex: sound.widthIndex, pan: sound.pan, up: up)
    }
}

/// What the person chose: the sound, how loud, and where it stays quiet.
public struct Settings: Equatable, Codable, Sendable {
    public var design = Design.presets[0].design
    /// The preset's name, or nil for a design of one's own.
    public var designName: String? = Design.presets[0].name
    public var volume = 0.6
    public var muted = false
    /// Apps it stays quiet in, by bundle identifier.
    public var mutedApps: [String] = []
    public var playsReleases = true
    public var playsRepeats = false

    public init() {}

    enum CodingKeys: String, CodingKey { case design, designName, volume, muted, mutedApps, playsReleases, playsRepeats }

    /// Reads saved settings as untrusted: anything missing or malformed keeps its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        design = (try? c.decodeIfPresent(Design.self, forKey: .design)).flatMap { $0 } ?? d.design
        designName = (try? c.decodeIfPresent(String.self, forKey: .designName)).flatMap { $0 }.map(Settings.cleanName)
        if designName?.isEmpty == true { designName = nil }
        let v = (try? c.decodeIfPresent(Double.self, forKey: .volume)).flatMap { $0 } ?? d.volume
        volume = v.isFinite ? min(1, max(0, v)) : d.volume
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)).flatMap { $0 } ?? d.muted
        let apps = (try? c.decodeIfPresent([String].self, forKey: .mutedApps)).flatMap { $0 } ?? []
        mutedApps = Array(apps.filter(Settings.isBundleID).prefix(200))
        playsReleases = (try? c.decodeIfPresent(Bool.self, forKey: .playsReleases)).flatMap { $0 } ?? d.playsReleases
        playsRepeats = (try? c.decodeIfPresent(Bool.self, forKey: .playsRepeats)).flatMap { $0 } ?? d.playsRepeats
    }

    public static func load(_ data: Data?) -> Settings {
        guard let data, let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    public func data() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func isBundleID(_ id: String) -> Bool {
        (1...255).contains(id.utf8.count) && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-" }
    }

    /// A name safe to show: no control characters or text-direction marks, at most 40 characters.
    public static func cleanName(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { !$0.properties.isBidiControl && !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).prefix(40).description
    }

    /// Whether a stroke should be heard with `app` in front.
    public func plays(_ stroke: Stroke, frontApp: String?) -> Bool {
        if muted || volume <= 0 { return false }
        if stroke.up && !playsReleases { return false }
        if let frontApp, mutedApps.contains(frontApp) { return false }
        return true
    }

    public mutating func setMuted(_ app: String, _ isMuted: Bool) {
        guard Settings.isBundleID(app) else { return }
        mutedApps.removeAll { $0 == app }
        if isMuted { mutedApps.append(app) }
    }

    /// Takes a design from a share link or code. False if it isn't one.
    public mutating func importDesign(_ text: String) -> Bool {
        guard let design = ShareCode.decode(text) else { return false }
        self.design = design
        designName = design.presetName
        return true
    }

    public mutating func choose(_ preset: Preset) {
        design = preset.design
        designName = preset.name
    }

    /// Changes one setting by hand, which makes the design one's own.
    public mutating func edit(_ change: (inout Design) -> Void) {
        change(&design)
        design.clamp()
        designName = design.presetName
    }
}
