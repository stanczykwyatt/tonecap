import Foundation
import Testing
@testable import ToneCore

@Suite struct ShareCodeTests {
    @Test func roundTripsEveryPreset() {
        for preset in Design.presets {
            let code = ShareCode.encode(preset.design)
            #expect(code.count == 19)
            #expect(ShareCode.decode(code) == preset.design)
        }
    }

    @Test func readsWholeLinks() {
        let design = Design.presets[1].design
        let code = ShareCode.encode(design)
        for link in [ShareCode.link(design), "https://x.test/?s=\(code)&n=Mine", "#s=\(code)", "  \(code)\n"] {
            #expect(ShareCode.decode(link) == design)
        }
        #expect(ShareCode.link(design) == "https://stanczykwyatt.github.io/tonecap/#s=\(code)")
    }

    @Test func refusesDamagedCodes() {
        let code = ShareCode.encode(Design())
        var flipped = Array(code)
        flipped[5] = flipped[5] == "A" ? "B" : "A"
        for bad in ["", "abc", String(flipped), String(code.dropLast()), code + "AA", "!!!!", String(repeating: "A", count: 65), "https://x.test/#s="] {
            #expect(ShareCode.decode(bad) == nil, "\(bad)")
        }
    }

    @Test func eachDesignHasOneCodeAndLinksReadLikeTheWeb() {
        let code = ShareCode.encode(Design())
        let alphabet = ShareCode.alphabet
        let last = alphabet.firstIndex(of: code.last!)!
        for spare in [1, 2, 3] {
            #expect(ShareCode.decode(String(code.dropLast()) + String(alphabet[last ^ spare])) == nil)
        }
        #expect(ShareCode.decode("https://x.test/?s=broken#s=\(code)") == Design())
        #expect(ShareCode.decode("\u{FEFF}\(code)") == Design())
    }

    @Test func seedsWrapLikeTheWeb() {
        _ = Engine.pressSeed(Design(), width: -3, variant: -9, up: false)
    }

    @Test func refusesValuesOutOfRange() {
        func forge(_ bytes: [UInt8]) -> String {
            let all = bytes + [ShareCode.check(bytes)]
            return Data(all).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let good: [UInt8] = [1] + Design().bytes
        #expect(ShareCode.decode(forge(good)) == Design())
        var slider = good; slider[2] = 101
        var option = good; option[1] = 3
        var plate = good; plate[6] = 5
        var version = good; version[0] = 2
        for bytes in [slider, option, plate, version] { #expect(ShareCode.decode(forge(bytes)) == nil) }
    }

    @Test func designInitClampsSliders() {
        let d = Design(switchType: .linear, spring: 140, lube: -4, bottomOut: 50, topOut: 50, plate: .brass, caseMaterial: .wood, foam: 0, keycap: .abs, thickness: 0, profile: .low, stabilizers: 100)
        #expect(d.spring == 100 && d.lube == 0)
    }

    @Test func savedDesignsAreReadLeniently() throws {
        let json = #"{"switch":"clicky","spring":140,"lube":"lots","plate":"steel","foam":12.6}"#
        let d = try JSONDecoder().decode(Design.self, from: Data(json.utf8))
        #expect(d.switchType == .clicky)
        #expect(d.spring == 100)
        #expect(d.lube == Design().lube)
        #expect(d.plate == Design().plate)
        #expect(d.foam == 13)
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(Design.presets[3].design))
        #expect(back == Design.presets[3].design)
    }

    @Test func presetsAreNamedAndDistinct() {
        #expect(Set(Design.presets.map(\.name)).count == Design.presets.count)
        #expect(Set(Design.presets.map(\.design)).count == Design.presets.count)
        #expect(Design.presets[0].design.presetName == "Deep thock")
        #expect(Design().presetName == nil)
    }
}

@Suite struct KeyboardTests {
    @Test func keyCodesAreUnique() {
        #expect(Set(Keyboard.keys.map(\.keyCode)).count == Keyboard.keys.count)
        #expect(Set(Keyboard.keys.map(\.code)).count == Keyboard.keys.count)
    }

    @Test func wideKeysGetTheirOwnSounds() {
        #expect(Keyboard.widths[Keyboard.sound(for: 49).widthIndex] == 6.25) // space
        #expect(Keyboard.widths[Keyboard.sound(for: 36).widthIndex] == 2.25) // return
        #expect(Keyboard.widths[Keyboard.sound(for: 51).widthIndex] == 2) // delete
        #expect(Keyboard.widths[Keyboard.sound(for: 60).widthIndex] == 2.75) // right shift
        #expect(Keyboard.widths[Keyboard.sound(for: 0).widthIndex] == 1) // A
    }

    @Test func panFollowsPosition() {
        let q = Keyboard.sound(for: 12).pan, p = Keyboard.sound(for: 35).pan, right = Keyboard.sound(for: 124).pan
        #expect(q < 0 && q < p && p < right && right > 0)
        #expect(Keyboard.keys.allSatisfy { abs($0.pan) <= 0.7 })
        #expect(Keyboard.sound(for: 200) == (0, 0))
    }

    @Test func nearestWidth() {
        #expect(Keyboard.widths[Keyboard.nearestWidthIndex(2.1)] == 2)
        #expect(Keyboard.widths[Keyboard.nearestWidthIndex(1.3)] == 1.25)
        #expect(Keyboard.widths[Keyboard.nearestWidthIndex(9)] == 6.25)
    }
}

@Suite struct TrackerTests {
    @Test func plainKeysPlayDownThenUp() {
        var t = KeyTracker()
        let down = t.handle(.down(keyCode: 0, isRepeat: false))
        #expect(down?.up == false && down?.keyCode == 0)
        do { let r = t.handle(.up(keyCode: 0)); #expect(r?.up == true) }
        do { let r = t.handle(.up(keyCode: 0)); #expect(r == nil, "no release for a key it didn't hear go down") }
    }

    @Test func autoRepeatIsSilentUnlessAskedFor() {
        var t = KeyTracker()
        _ = t.handle(.down(keyCode: 0, isRepeat: false))
        do { let r = t.handle(.down(keyCode: 0, isRepeat: true)); #expect(r == nil) }
        t.playsRepeats = true
        do { let r = t.handle(.down(keyCode: 0, isRepeat: true)); #expect(r != nil) }
        do { let r = t.handle(.up(keyCode: 0)); #expect(r?.up == true) }
    }

    @Test func modifiersFromFlags() {
        var t = KeyTracker()
        let shift: UInt64 = 0x20000
        do { let r = t.handle(.flagsChanged(keyCode: 56, flags: shift)); #expect(r?.up == false) }
        do { let r = t.handle(.flagsChanged(keyCode: 60, flags: shift)); #expect(r?.up == false, "the other shift goes down while one is held") }
        do { let r = t.handle(.flagsChanged(keyCode: 60, flags: shift)); #expect(r?.up == true, "right shift up, left still held") }
        do { let r = t.handle(.flagsChanged(keyCode: 56, flags: 0)); #expect(r?.up == true) }
        do { let r = t.handle(.flagsChanged(keyCode: 56, flags: 0)); #expect(r == nil, "already up") }
        do { let r = t.handle(.flagsChanged(keyCode: 55, flags: 0x100000)); #expect(r?.widthIndex == Keyboard.nearestWidthIndex(1.25)) }
    }

    @Test func capsLockPlaysOnPress() {
        var t = KeyTracker()
        do { let r = t.handle(.flagsChanged(keyCode: 57, flags: 0x10000)); #expect(r?.up == false) }
        do { let r = t.handle(.flagsChanged(keyCode: 57, flags: 0)); #expect(r?.up == false) }
    }

    @Test func unknownFlagKeysAreIgnored() {
        var t = KeyTracker()
        do { let r = t.handle(.flagsChanged(keyCode: 10, flags: 0x20000)); #expect(r == nil) }
    }

    @Test func resetForgetsHeldKeys() {
        var t = KeyTracker()
        _ = t.handle(.down(keyCode: 3, isRepeat: false))
        t.reset()
        do { let r = t.handle(.up(keyCode: 3)); #expect(r == nil) }
    }

    @Test func heldSetStaysSmall() {
        var t = KeyTracker()
        for code in 0..<200 { _ = t.handle(.down(keyCode: UInt16(code), isRepeat: false)) }
        #expect(t.held.count <= 65)
    }
}

@Suite struct PickerTests {
    @Test func neverTheSameVariantTwiceInARow() {
        var picker = VariantPicker(seed: 42)
        var last = -1
        var seen = Set<Int>()
        for _ in 0..<500 {
            let v = picker.next(widthIndex: 0)
            #expect(v != last && (0..<8).contains(v))
            last = v
            seen.insert(v)
        }
        #expect(seen.count == 8)
    }

    @Test func deterministicForASeed() {
        var a = VariantPicker(seed: 7), b = VariantPicker(seed: 7)
        for _ in 0..<20 { let x = a.next(widthIndex: 1), y = b.next(widthIndex: 1); #expect(x == y) }
        var zero = VariantPicker(seed: 0)
        let z = zero.next(widthIndex: 0)
        #expect((0..<8).contains(z))
    }
}

@Suite struct BankTests {
    @Test func holdsEverySound() {
        let bank = SoundBank(design: Design.presets[0].design, sampleRate: 24000, variants: 2)
        #expect(bank.sounds.count == Keyboard.widths.count)
        #expect(bank.sounds.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.count == 2 } })
        let s = bank.sound(widthIndex: 7, variant: 3, up: true)
        #expect(s == Engine.render(bank.design, width: 6.25, variant: 1, up: true, sampleRate: 24000))
    }
}

@Suite struct SettingsTests {
    let stroke = Stroke(keyCode: 0, widthIndex: 0, pan: 0, up: false)
    let release = Stroke(keyCode: 0, widthIndex: 0, pan: 0, up: true)

    @Test func defaultsPlay() {
        let s = Settings()
        #expect(s.plays(stroke, frontApp: "com.example.Notes"))
        #expect(s.designName == "Deep thock")
    }

    @Test func muteVolumeAndReleases() {
        var s = Settings()
        s.muted = true
        #expect(!s.plays(stroke, frontApp: nil))
        s.muted = false
        s.volume = 0
        #expect(!s.plays(stroke, frontApp: nil))
        s.volume = 0.5
        s.playsReleases = false
        #expect(s.plays(stroke, frontApp: nil) && !s.plays(release, frontApp: nil))
    }

    @Test func perAppMute() {
        var s = Settings()
        s.setMuted("com.example.Meetings", true)
        s.setMuted("com.example.Meetings", true)
        #expect(s.mutedApps == ["com.example.Meetings"])
        #expect(!s.plays(stroke, frontApp: "com.example.Meetings"))
        #expect(s.plays(stroke, frontApp: "com.example.Notes"))
        s.setMuted("com.example.Meetings", false)
        #expect(s.mutedApps.isEmpty)
        s.setMuted("not a bundle id; rm -rf", true)
        #expect(s.mutedApps.isEmpty)
    }

    @Test func importAndEdit() {
        var s = Settings()
        let refused = s.importDesign("https://example.test/nothing")
        let taken = s.importDesign(ShareCode.link(Design.presets[2].design))
        #expect(!refused && taken)
        #expect(s.design == Design.presets[2].design && s.designName == "Crisp click")
        s.edit { $0.foam = 300 }
        #expect(s.design.foam == 100 && s.designName == nil)
        s.choose(Design.presets[4])
        #expect(s.designName == "Heavy brass")
    }

    @Test func roundTripsAndReadsUntrustedData() {
        var s = Settings()
        s.volume = 0.3
        s.setMuted("com.example.Meetings", true)
        #expect(Settings.load(s.data()) == s)
        #expect(Settings.load(nil) == Settings())
        #expect(Settings.load(Data("garbage".utf8)) == Settings())
        let json = #"{"volume":7,"mutedApps":["com.example.A","bad id","‮evil"],"designName":"Mine‮\u0007 board","muted":"yes"}"#
        let read = Settings.load(Data(json.utf8))
        #expect(read.volume == 1)
        #expect(read.mutedApps == ["com.example.A"])
        #expect(read.designName == "Mine board")
        #expect(read.muted == false)
        #expect(read.design == Settings().design)
    }

    @Test func namesAreCleaned() {
        #expect(Settings.cleanName(String(repeating: "x", count: 80)).count == 40)
        #expect(Settings.cleanName("  Lab\u{200F} board\n") == "Lab board")
    }
}
