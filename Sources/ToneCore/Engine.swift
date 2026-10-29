import Foundation

// The sound engine, a line-by-line port of docs/engine/tonecap.js. The comments there explain the
// model; this file keeps the same names, steps and order, so the two give the same samples to
// within rounding. EngineTests compares them against renders the JavaScript made.

enum Random {
    static func fmix32(_ value: UInt32) -> UInt32 {
        var h = value
        h ^= h >> 16
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        h = h &* 0xC2B2_AE35
        return h ^ (h >> 16)
    }

    /// xorshift32, giving numbers in 0..<1.
    struct Generator {
        var x: UInt32
        init(_ seed: UInt32) { x = seed == 0 ? 0x9E37_79B9 : seed }
        mutating func next() -> Double {
            x ^= x << 13
            x ^= x >> 17
            x ^= x << 5
            return Double(x) / 4_294_967_296
        }
    }
}

public enum Engine {
    /// FNV-1a over the design's bytes, so each design varies in its own way.
    public static func designHash(_ design: Design) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        for b in design.bytes { h = (h ^ UInt32(b)) &* 0x0100_0193 }
        return h
    }

    /// The seed for one variant of one key size, pressed or released.
    public static func pressSeed(_ design: Design, width: Double, variant: Int, up: Bool) -> UInt32 {
        var h = designHash(design)
        h ^= UInt32(truncatingIfNeeded: Int((width * 4).rounded()) + 1) &* 0x9E37_79B1
        h ^= UInt32(truncatingIfNeeded: variant + 1) &* 0x85EB_CA6B
        if up { h ^= 0xC2B2_AE35 }
        return Random.fmix32(h)
    }

    /// How long a render is, in seconds.
    public static func duration(width: Double, up: Bool) -> Double {
        (up ? 0.13 : 0.17) + (width >= 6 ? 0.04 : 0)
    }

    struct PlateModel { let f, tau, gain: Double; let ratios: [Double] }
    struct CaseModel { let f, tau, gain, ping, pingF: Double }

    static func plateModel(_ plate: Plate) -> PlateModel {
        switch plate {
        case .aluminum: PlateModel(f: 1480, tau: 0.016, gain: 0.55, ratios: [1, 1.71, 2.47, 3.32])
        case .brass: PlateModel(f: 1020, tau: 0.024, gain: 0.6, ratios: [1, 1.68, 2.41, 3.2])
        case .polycarbonate: PlateModel(f: 690, tau: 0.007, gain: 0.35, ratios: [1, 1.8, 2.6, 3.5])
        case .fr4: PlateModel(f: 1180, tau: 0.011, gain: 0.45, ratios: [1, 1.74, 2.5, 3.3])
        case .pom: PlateModel(f: 800, tau: 0.005, gain: 0.3, ratios: [1, 1.82, 2.66, 3.6])
        }
    }

    static func caseModel(_ material: CaseMaterial) -> CaseModel {
        switch material {
        case .plastic: CaseModel(f: 360, tau: 0.02, gain: 0.5, ping: 0, pingF: 2850)
        case .aluminum: CaseModel(f: 540, tau: 0.012, gain: 0.3, ping: 0.12, pingF: 2850)
        case .wood: CaseModel(f: 290, tau: 0.009, gain: 0.38, ping: 0, pingF: 2850)
        }
    }

    static func profilePitch(_ p: Profile) -> Double { switch p { case .low: 1.15; case .medium: 1; case .tall: 0.8 } }
    static func profileRing(_ p: Profile) -> Double { switch p { case .low: 0.9; case .medium: 1; case .tall: 1.1 } }
    static func profileGain(_ p: Profile) -> Double { switch p { case .low: 1.05; case .medium: 1; case .tall: 0.75 } }
    static let capRatios: [Double] = [1, 1.52, 2.11, 2.9, 3.7]
    static let capGains: [Double] = [1, 0.7, 0.5, 0.32, 0.2]
    static let plateGains: [Double] = [1, 0.6, 0.4, 0.25]
    static let clickModes: [(Double, Double, Double)] = [(3300, 0.007, 1), (4700, 0.005, 0.8), (6900, 0.004, 0.5)]
    static let rattleModes: [(Double, Double, Double)] = [(1850, 0.012, 1), (3150, 0.01, 0.7), (5200, 0.007, 0.4)]

    enum Bank: Int, CaseIterable { case cap, plate, kase, thump, spring, click, rattle }
    enum Filter { case band, high }
    struct Burst { let start, length, amp: Double; let filter: Filter; let f, q: Double; let offset: Int }

    /// One press (or release) of one key, before it's scaled to the design's level.
    /// `width` is the key's width in units (1 for a letter, 6.25 for a spacebar).
    public static func renderRaw(_ d: Design, width: Double, variant: Int, up: Bool, sampleRate: Double) -> [Double] {
        let fs = sampleRate
        let n = Int((duration(width: width, up: up) * fs).rounded())
        var rng = Random.Generator(pressSeed(d, width: width, variant: variant, up: up))
        func jitter(_ amount: Double) -> Double { 1 + (rng.next() * 2 - 1) * amount }
        let vel = jitter(0.08)
        let travelJ = jitter(0.08)
        let capJ = jitter(0.012)
        let plateJ = jitter(0.012)
        let caseJ = jitter(0.01)
        let widthJ = jitter(0.1)
        let rattle1 = rng.next()
        let rattle2 = rng.next()
        let rattle3 = rng.next()

        let spring = Double(d.spring) / 100, lube = Double(d.lube) / 100, bottom = Double(d.bottomOut) / 100, top = Double(d.topOut) / 100
        let foam = Double(d.foam) / 100, thick = Double(d.thickness) / 100, stab = Double(d.stabilizers) / 100
        let pbt = d.keycap == .pbt
        let soft = d.plate == .polycarbonate || d.plate == .pom ? 1.15 : 1
        let stabilized = width >= 2
        let rattle = stabilized ? 1 - stab : 0
        let wide = min(width, 6.25) - 1

        let capPitch = 2400 * (pbt ? 0.86 : 1) * (1.25 - 0.5 * thick) * profilePitch(d.profile) * pow(width, -0.3) * capJ * (up ? 1.15 : 1)
        let capTau = (pbt ? 0.004 : 0.0065) * (1.2 - 0.4 * thick) * profileRing(d.profile)
        let plate = plateModel(d.plate)
        let kase = caseModel(d.caseMaterial)
        var banks = [[(Double, Double, Double)]](repeating: [], count: Bank.allCases.count)
        banks[Bank.cap.rawValue] = capRatios.enumerated().map { i, r in
            (capPitch * r, capTau / r.squareRoot(), (pbt ? 0.9 : 1.1) * profileGain(d.profile) * capGains[i])
        }
        banks[Bank.plate.rawValue] = plate.ratios.enumerated().map { i, r in
            (plate.f * plateJ * r, (plate.tau * (1 - 0.3 * foam)) / r.squareRoot(), plate.gain * plateGains[i])
        }
        banks[Bank.kase.rawValue] = [
            (kase.f * caseJ * pow(width, -0.12), kase.tau * (1 - 0.6 * foam), 0.6 * kase.gain * (1 - 0.75 * foam) * (1 + 0.15 * wide)),
            (kase.f * caseJ * 2.3, kase.tau * 0.6 * (1 - 0.6 * foam), 0.6 * kase.gain * 0.4 * (1 - 0.75 * foam)),
            (kase.pingF * caseJ, 0.06 * (1 - 0.5 * foam), kase.ping * (1 - 0.85 * foam)),
        ]
        banks[Bank.thump.rawValue] = [(140 * pow(width, -0.15), 0.008, 0.12 * (1 + 0.2 * wide))]
        banks[Bank.spring.rawValue] = [(4300 + 2200 * spring, 0.045, 0.06 * (1 - lube) * (1 - lube))]
        banks[Bank.click.rawValue] = clickModes
        banks[Bank.rattle.rawValue] = rattleModes
        var excite = [[Double]?](repeating: nil, count: Bank.allCases.count)

        func pulse(_ bank: Bank, _ time: Double, _ w: Double, _ amp: Double) {
            if amp == 0 { return }
            if excite[bank.rawValue] == nil { excite[bank.rawValue] = [Double](repeating: 0, count: n) }
            let start = time * fs
            let nW = max(1, w * fs)
            let first = Int(start.rounded(.down))
            let count = Int(nW.rounded(.up)) + 1
            for k in 0...count {
                let pos = first + k
                let phase = (Double(pos) - start) / nW
                if pos >= 0, pos < n, phase >= 0, phase <= 1 {
                    excite[bank.rawValue]![pos] += amp * sin(Double.pi * phase) * (Double.pi / (2 * nW))
                }
            }
        }
        func impact(_ time: Double, _ w: Double, _ amp: Double, _ gains: [(Bank, Double)]) {
            for (bank, gain) in gains { pulse(bank, time, w, amp * gain) }
        }

        var noiseRng = Random.Generator(Random.fmix32(pressSeed(d, width: width, variant: variant, up: up) ^ 0x5BD1_E995))
        var noise = [Double](repeating: 0, count: n)
        for i in 0..<n { noise[i] = noiseRng.next() * 2 - 1 }
        var layers: [Burst] = []
        func burst(_ start: Double, _ length: Double, _ amp: Double, _ filter: Filter, _ f: Double, _ q: Double) {
            if amp > 0 { layers.append(Burst(start: start, length: length, amp: amp, filter: filter, f: f, q: q, offset: layers.count * 997)) }
        }

        let springGain: Double = banks[Bank.spring.rawValue][0].2 > 0 ? 1 : 0
        if !up {
            let travel = (0.006 + 0.008 * spring) * travelJ
            let scratch = (0.05 * pow(1 - lube, 1.5) + 0.008) * (d.switchType == .tactile ? 1.4 : 1)
            burst(0, travel, scratch * vel, .band, 3000 + 1500 * spring, 0.7)
            if d.switchType == .tactile {
                burst(travel * 0.35, 0.003, 0.12 * (1 - 0.5 * lube) * vel, .band, 2200, 0.9)
                impact(travel * 0.35, 0.001, 0.1 * vel, [(.cap, 1)])
            }
            if d.switchType == .clicky {
                let t = travel * 0.45
                impact(t, 0.00008, 1.1 * vel, [(.click, 1), (.cap, 0.25), (.plate, 0.2)])
                burst(t, 0.0007, 0.5 * vel, .band, 4500, 1.2)
            }
            let w = (0.00065 - 0.00055 * bottom) * widthJ * soft
            let amp = vel * (0.6 + 0.4 * bottom)
            impact(travel, w, amp, [(.cap, 1), (.plate, 1), (.kase, 1), (.thump, 1), (.spring, springGain)])
            burst(travel, 2 * w + 0.0003, 0.15 * amp * (0.3 + bottom), .high, 2500, 0.7)
            if stabilized {
                impact(travel + 0.0006 + 0.0014 * rattle1, 0.0001, 0.35 * rattle * amp, [(.rattle, 1)])
                impact(travel + 0.0016 + 0.0018 * rattle2, 0.0001, 0.25 * rattle * amp, [(.rattle, 1), (.cap, 0.2)])
                impact(travel + 0.0003 * rattle3, 0.0008, 0.15 * stab * amp, [(.kase, 1), (.thump, 1)])
            }
        } else {
            let back = (0.013 - 0.006 * spring) * travelJ
            let start = 0.002
            burst(start, back, (0.035 * pow(1 - lube, 1.5) + 0.006) * vel, .band, 3300 + 1500 * spring, 0.7)
            if d.switchType == .clicky {
                let t = start + back * 0.6
                impact(t, 0.00008, 0.45 * vel, [(.click, 1), (.cap, 0.2)])
                burst(t, 0.0006, 0.2 * vel, .band, 4500, 1.2)
            }
            let w = (0.0005 - 0.0004 * top) * widthJ
            let amp = vel * (0.32 + 0.33 * top) * (1 - 0.3 * lube)
            impact(start + back, w, amp, [(.cap, 0.8), (.plate, 0.45), (.kase, 0.3), (.thump, 0.1), (.spring, 1.2 * springGain)])
            burst(start + back, 2 * w + 0.0003, 0.05 * amp * (0.3 + top), .high, 3000, 0.7)
            if stabilized {
                impact(start + back + 0.0005 + 0.0012 * rattle1, 0.0001, 0.4 * rattle * amp, [(.rattle, 1)])
                impact(start + back + 0.0014 + 0.0016 * rattle2, 0.0001, 0.3 * rattle * amp, [(.rattle, 1)])
            }
        }

        var out = [Double](repeating: 0, count: n)
        let nyquistGuard = 0.45 * fs
        out.withUnsafeMutableBufferPointer { out in
            for bank in Bank.allCases {
                guard let e = excite[bank.rawValue] else { continue }
                for (f, tau, gain) in banks[bank.rawValue] {
                    if gain == 0 || f >= nyquistGuard { continue }
                    let w = (2 * Double.pi * f) / fs
                    let r = exp(-1 / (tau * fs))
                    let a1 = 2 * r * cos(w)
                    let a2 = -r * r
                    let b = gain * sin(w)
                    var y1 = 0.0, y2 = 0.0
                    for i in 0..<n {
                        let y = a1 * y1 + a2 * y2 + b * e[i]
                        out[i] += y
                        y2 = y1
                        y1 = y
                    }
                }
            }

            for layer in layers {
                let c = biquad(layer.filter, min(layer.f, nyquistGuard), layer.q, fs)
                let first = max(0, Int((layer.start * fs).rounded(.down)))
                let count = max(1, Int((layer.length * fs).rounded()))
                var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
                let tail = min(n - first, count + Int((0.004 * fs).rounded()))
                if tail <= 0 { continue }
                for k in 0..<tail {
                    let env = k < count ? sin((Double.pi * (Double(k) + 0.5)) / Double(count)) : 0
                    let x = noise[(first + k + layer.offset) % n] * env * layer.amp
                    let y = c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
                    x2 = x1; x1 = x; y2 = y1; y1 = y
                    out[first + k] += y
                }
            }

            let R = exp((-2 * Double.pi * 30) / fs)
            var px = 0.0, py = 0.0
            for i in 0..<n {
                let y = out[i] - px + R * py
                px = out[i]
                py = y
                out[i] = y
            }
            let fade = min(n, Int((0.008 * fs).rounded()))
            for k in 0..<fade { out[n - 1 - k] *= Double(k) / Double(fade) }
        }
        return out
    }

    static func biquad(_ kind: Filter, _ f: Double, _ q: Double, _ fs: Double) -> [Double] {
        let w0 = (2 * Double.pi * f) / fs
        let cosine = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        switch kind {
        case .band: return [alpha / a0, 0, -alpha / a0, (-2 * cosine) / a0, (1 - alpha) / a0]
        case .high: return [(1 + cosine) / 2 / a0, -(1 + cosine) / a0, (1 + cosine) / 2 / a0, (-2 * cosine) / a0, (1 - alpha) / a0]
        }
    }

    /// The scale that brings a letter key's press to a set peak, so every design plays at about the same level.
    public static func designGain(_ design: Design, sampleRate: Double) -> Double {
        let p = renderRaw(design, width: 1, variant: 0, up: false, sampleRate: sampleRate).reduce(0) { max($0, abs($1)) }
        return p > 0 ? 0.7 / p : 0
    }

    /// One press or release, ready to play: mono samples peaking near 0.7 for a letter key.
    public static func render(_ design: Design, width: Double, variant: Int, up: Bool, sampleRate: Double, gain: Double? = nil) -> [Float] {
        let g = gain ?? designGain(design, sampleRate: sampleRate)
        return renderRaw(design, width: width, variant: variant, up: up, sampleRate: sampleRate).map { Float(max(-1, min(1, $0 * g))) }
    }
}
