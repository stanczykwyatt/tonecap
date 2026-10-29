import Foundation

// A keyboard build, the presets, and the short codes that put one in a link. Mirrors the top of
// docs/engine/tonecap.js; the tests check both read and write the same codes.

public enum SwitchType: String, CaseIterable, Codable, Sendable { case linear, tactile, clicky }
public enum Plate: String, CaseIterable, Codable, Sendable { case aluminum, brass, polycarbonate, fr4, pom }
public enum CaseMaterial: String, CaseIterable, Codable, Sendable { case plastic, aluminum, wood }
public enum Keycap: String, CaseIterable, Codable, Sendable { case pbt, abs }
public enum Profile: String, CaseIterable, Codable, Sendable { case low, medium, tall }

/// Every setting of a build. Sliders run from 0 to 100.
public struct Design: Equatable, Hashable, Codable, Sendable {
    public var switchType: SwitchType = .linear
    public var spring = 50
    public var lube = 60
    public var bottomOut = 60
    public var topOut = 45
    public var plate: Plate = .aluminum
    public var caseMaterial: CaseMaterial = .plastic
    public var foam = 40
    public var keycap: Keycap = .pbt
    public var thickness = 60
    public var profile: Profile = .medium
    public var stabilizers = 70

    public init() {}

    public init(
        switchType: SwitchType, spring: Int, lube: Int, bottomOut: Int, topOut: Int, plate: Plate,
        caseMaterial: CaseMaterial, foam: Int, keycap: Keycap, thickness: Int, profile: Profile, stabilizers: Int
    ) {
        self.switchType = switchType
        self.spring = spring
        self.lube = lube
        self.bottomOut = bottomOut
        self.topOut = topOut
        self.plate = plate
        self.caseMaterial = caseMaterial
        self.foam = foam
        self.keycap = keycap
        self.thickness = thickness
        self.profile = profile
        self.stabilizers = stabilizers
        clamp()
    }

    enum CodingKeys: String, CodingKey {
        case switchType = "switch", spring, lube, bottomOut, topOut, plate, caseMaterial = "case", foam, keycap, thickness, profile, stabilizers
    }

    /// Reads a saved design leniently: a missing or unknown value keeps its default, like `normalize` in the engine.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap(T.init(rawValue:)) ?? fallback
        }
        func number(_ key: CodingKeys, _ fallback: Int) -> Int {
            guard let n = (try? c.decodeIfPresent(Double.self, forKey: key)).flatMap({ $0 }), n.isFinite else { return fallback }
            return Int(min(100, max(0, n)).rounded())
        }
        let d = Design()
        switchType = value(.switchType, d.switchType)
        spring = number(.spring, d.spring)
        lube = number(.lube, d.lube)
        bottomOut = number(.bottomOut, d.bottomOut)
        topOut = number(.topOut, d.topOut)
        plate = value(.plate, d.plate)
        caseMaterial = value(.caseMaterial, d.caseMaterial)
        foam = number(.foam, d.foam)
        keycap = value(.keycap, d.keycap)
        thickness = number(.thickness, d.thickness)
        profile = value(.profile, d.profile)
        stabilizers = number(.stabilizers, d.stabilizers)
    }

    /// Keeps every slider within 0...100.
    public mutating func clamp() {
        for path in Design.sliders { self[keyPath: path] = min(100, max(0, self[keyPath: path])) }
    }

    nonisolated(unsafe) public static let sliders: [WritableKeyPath<Design, Int>] = [\.spring, \.lube, \.bottomOut, \.topOut, \.foam, \.thickness, \.stabilizers]

    /// One byte per setting, in the order the share code uses.
    public var bytes: [UInt8] {
        var d = self
        d.clamp()
        return [
            UInt8(SwitchType.allCases.firstIndex(of: d.switchType)!), UInt8(d.spring), UInt8(d.lube), UInt8(d.bottomOut), UInt8(d.topOut),
            UInt8(Plate.allCases.firstIndex(of: d.plate)!), UInt8(CaseMaterial.allCases.firstIndex(of: d.caseMaterial)!), UInt8(d.foam),
            UInt8(Keycap.allCases.firstIndex(of: d.keycap)!), UInt8(d.thickness), UInt8(Profile.allCases.firstIndex(of: d.profile)!), UInt8(d.stabilizers),
        ]
    }
}

public struct Preset: Equatable, Sendable {
    public let name: String
    public let design: Design
}

public extension Design {
    /// Starting points, named for how they sound, not after any product. The same list as the engine's.
    static let presets: [Preset] = [
        Preset(name: "Deep thock", design: Design(switchType: .linear, spring: 55, lube: 85, bottomOut: 55, topOut: 35, plate: .polycarbonate, caseMaterial: .wood, foam: 70, keycap: .pbt, thickness: 90, profile: .tall, stabilizers: 90)),
        Preset(name: "Bright clack", design: Design(switchType: .linear, spring: 40, lube: 30, bottomOut: 85, topOut: 75, plate: .aluminum, caseMaterial: .aluminum, foam: 10, keycap: .abs, thickness: 20, profile: .low, stabilizers: 60)),
        Preset(name: "Crisp click", design: Design(switchType: .clicky, spring: 60, lube: 10, bottomOut: 70, topOut: 60, plate: .aluminum, caseMaterial: .plastic, foam: 20, keycap: .abs, thickness: 45, profile: .medium, stabilizers: 50)),
        Preset(name: "Soft tactile", design: Design(switchType: .tactile, spring: 62, lube: 70, bottomOut: 40, topOut: 30, plate: .pom, caseMaterial: .plastic, foam: 80, keycap: .pbt, thickness: 70, profile: .medium, stabilizers: 85)),
        Preset(name: "Heavy brass", design: Design(switchType: .linear, spring: 85, lube: 60, bottomOut: 70, topOut: 55, plate: .brass, caseMaterial: .aluminum, foam: 40, keycap: .pbt, thickness: 75, profile: .tall, stabilizers: 80)),
        Preset(name: "Quiet office", design: Design(switchType: .tactile, spring: 50, lube: 50, bottomOut: 20, topOut: 15, plate: .polycarbonate, caseMaterial: .plastic, foam: 100, keycap: .pbt, thickness: 60, profile: .low, stabilizers: 75)),
        Preset(name: "Hollow plastic", design: Design(switchType: .linear, spring: 45, lube: 20, bottomOut: 75, topOut: 65, plate: .fr4, caseMaterial: .plastic, foam: 0, keycap: .abs, thickness: 30, profile: .medium, stabilizers: 20)),
    ]

    /// The preset this design is, if it's exactly one.
    var presetName: String? { Design.presets.first { $0.design == self }?.name }
}

// Share codes: a version byte, one byte per setting and a check byte, in base64url.

public enum ShareCode {
    static let version: UInt8 = 1
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    public static let siteURL = "https://stanczykwyatt.github.io/tonecap/"

    public static func encode(_ design: Design) -> String {
        var bytes = [version] + design.bytes
        bytes.append(check(bytes))
        var code = ""
        var i = 0
        while i < bytes.count {
            let b1 = Int(bytes[i])
            let b2 = i + 1 < bytes.count ? Int(bytes[i + 1]) : 0
            let b3 = i + 2 < bytes.count ? Int(bytes[i + 2]) : 0
            let n = (b1 << 16) | (b2 << 8) | b3
            let chars = i + 2 < bytes.count ? 4 : i + 1 < bytes.count ? 3 : 2
            for c in 0..<chars { code.append(alphabet[(n >> (18 - 6 * c)) & 63]) }
            i += 3
        }
        return code
    }

    /// The link the website opens this design with.
    public static func link(_ design: Design) -> String { siteURL + "#s=" + encode(design) }

    static func check(_ bytes: [UInt8]) -> UInt8 {
        var sum: UInt8 = 0
        for b in bytes { sum &+= b }
        return sum ^ 0xA5
    }

    /// A design from a code, or from a whole link holding one (`…#s=CODE` or `…?s=CODE`).
    /// Returns nil for anything that isn't a valid code, rather than guessing.
    public static func decode(_ text: String) -> Design? {
        var code = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))))
        // The last s= in a link wins, so a code after the # beats one in the query.
        if let match = code.matches(of: /[#?&]s=([A-Za-z0-9_-]+)/).last { code = match.1 }
        guard (2...64).contains(code.count), code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        var bytes: [UInt8] = []
        var bits = 0, value = 0
        for char in code {
            value = (value << 6) | alphabet.firstIndex(of: char)!
            bits += 6
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((value >> bits) & 255))
                value &= (1 << bits) - 1
            }
        }
        // Leftover bits must be zero, so each design has exactly one code.
        guard value == 0, bytes.count == 14, bytes[0] == version, check(Array(bytes.dropLast())) == bytes.last else { return nil }
        func option<T: CaseIterable>(_ byte: UInt8, _: T.Type) -> T? where T.AllCases == [T] {
            Int(byte) < T.allCases.count ? T.allCases[Int(byte)] : nil
        }
        let sliders = [2, 3, 4, 5, 8, 10, 12].map { Int(bytes[$0]) }
        guard sliders.allSatisfy({ $0 <= 100 }),
              let switchType = option(bytes[1], SwitchType.self), let plate = option(bytes[6], Plate.self),
              let kase = option(bytes[7], CaseMaterial.self), let keycap = option(bytes[9], Keycap.self),
              let profile = option(bytes[11], Profile.self)
        else { return nil }
        return Design(
            switchType: switchType, spring: sliders[0], lube: sliders[1], bottomOut: sliders[2], topOut: sliders[3], plate: plate,
            caseMaterial: kase, foam: sliders[4], keycap: keycap, thickness: sliders[5], profile: profile, stabilizers: sliders[6]
        )
    }
}
