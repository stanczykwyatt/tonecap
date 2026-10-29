import Foundation
import Testing
@testable import ToneCore

/// The renders, codes and key table the JavaScript engine made (scripts/make-fixtures.mjs).
struct Fixture: Decodable {
    struct Seed: Decodable { let width: Double; let variant: Int; let up: Bool; let seed: UInt32 }
    struct Named: Decodable { let name: String; let design: Design; let code: String; let hash: UInt32; let seeds: [Seed] }
    struct KeyRow: Decodable { let code: String; let keyCode: UInt16; let x: Double; let width: Double; let pan: Double }
    struct Case: Decodable {
        let name: String; let width: Double; let variant: Int; let up: Bool; let sampleRate: Double
        let gain: Double; let length: Int; let stride: Int; let samples: [Double]
    }
    let designs: [Named]
    let keys: [KeyRow]
    let cases: [Case]

    static let shared: Fixture = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/engine.json")
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()
}

@Suite struct EngineTests {
    let fixture = Fixture.shared

    @Test func designsReadTheSameAsTheWeb() {
        #expect(fixture.designs.count == Design.presets.count + 1)
        #expect(fixture.designs[0].design == Design())
        for (named, preset) in zip(fixture.designs.dropFirst(), Design.presets) {
            #expect(named.name == preset.name)
            #expect(named.design == preset.design)
        }
    }

    @Test func shareCodesMatchTheWeb() {
        for named in fixture.designs {
            #expect(ShareCode.encode(named.design) == named.code)
            #expect(ShareCode.decode(named.code) == named.design)
        }
    }

    @Test func seedsMatchTheWeb() {
        for named in fixture.designs {
            #expect(Engine.designHash(named.design) == named.hash)
            for s in named.seeds {
                #expect(Engine.pressSeed(named.design, width: s.width, variant: s.variant, up: s.up) == s.seed)
            }
        }
    }

    @Test func keyTableMatchesTheWeb() {
        #expect(fixture.keys.count == Keyboard.keys.count)
        for (row, key) in zip(fixture.keys, Keyboard.keys) {
            #expect(row.code == key.code && row.keyCode == key.keyCode && row.x == key.x && row.width == key.width)
            #expect(abs(row.pan - key.pan) < 1e-6)
        }
    }

    /// The heart of it: Swift renders the same sound as the browser, sample for sample, to within
    /// rounding (the two use different math libraries for sin, cos and exp).
    @Test(arguments: Fixture.shared.cases.indices)
    func rendersMatchTheWeb(index: Int) {
        let c = fixture.cases[index]
        let design = fixture.designs.first { $0.name == c.name }!.design
        let gain = Engine.designGain(design, sampleRate: c.sampleRate)
        #expect(abs(gain - c.gain) / c.gain < 1e-5)
        let samples = Engine.render(design, width: c.width, variant: c.variant, up: c.up, sampleRate: c.sampleRate)
        #expect(samples.count == c.length)
        var worst = 0.0
        for (i, expected) in c.samples.enumerated() {
            worst = max(worst, abs(Double(samples[i * c.stride]) - expected))
        }
        #expect(worst < 2e-5, "largest difference \(worst) in \(c.name)")
    }

    @Test func rendersAreDeterministicAndBounded() {
        let design = Design.presets[2].design
        let a = Engine.render(design, width: 1, variant: 4, up: false, sampleRate: 48000)
        #expect(a == Engine.render(design, width: 1, variant: 4, up: false, sampleRate: 48000))
        #expect(a != Engine.render(design, width: 1, variant: 5, up: false, sampleRate: 48000))
        #expect(a.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(abs(a.map { abs($0) }.max()! - 0.7) < 0.1)
        #expect(a.last == 0)
    }

    @Test func everyWidthAndDirectionRenders() {
        for preset in Design.presets {
            for width in Keyboard.widths {
                for up in [false, true] {
                    let s = Engine.render(preset.design, width: width, variant: 1, up: up, sampleRate: 44100)
                    #expect(s.count == Int((Engine.duration(width: width, up: up) * 44100).rounded()))
                    #expect(s.contains { $0 != 0 })
                }
            }
        }
    }

    @Test func releasesAreQuieterThanPresses() {
        func energy(_ s: [Float]) -> Float { s.reduce(0) { $0 + $1 * $1 } }
        for preset in Design.presets {
            let down = Engine.render(preset.design, width: 1, variant: 0, up: false, sampleRate: 48000)
            let up = Engine.render(preset.design, width: 1, variant: 0, up: true, sampleRate: 48000)
            #expect(energy(up) < energy(down))
        }
    }

    @Test func seedsAreDistinct() {
        var seen = Set<UInt32>()
        for width in Keyboard.widths { for v in 0..<8 { for up in [false, true] { seen.insert(Engine.pressSeed(Design(), width: width, variant: v, up: up)) } } }
        #expect(seen.count == Keyboard.widths.count * 16)
    }
}
