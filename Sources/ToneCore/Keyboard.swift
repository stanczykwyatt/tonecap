import Foundation

/// One physical key: where it sits and how wide it is. Only key codes, never characters.
public struct Key: Equatable, Sendable {
    /// The name the web uses (`KeyboardEvent.code`), kept so the two tables can be compared.
    public let code: String
    /// The macOS virtual key code.
    public let keyCode: UInt16
    /// Distance from the board's left edge, in key units.
    public let x: Double
    public let width: Double

    /// Stereo position, -1 left to 1 right.
    public var pan: Double { Keyboard.pan(x: x + width / 2) }
}

public enum Keyboard {
    public static let boardWidth = 18.25

    /// The key widths that get their own sounds. Every key uses the nearest one.
    public static let widths: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.75, 6.25]

    /// A US layout with a navigation cluster: the same table as the engine's `KEYS`.
    public static let keys: [Key] = [
        ("Escape", 53, 0, 1), ("F1", 122, 2, 1), ("F2", 120, 3, 1), ("F3", 99, 4, 1), ("F4", 118, 5, 1),
        ("F5", 96, 6.5, 1), ("F6", 97, 7.5, 1), ("F7", 98, 8.5, 1), ("F8", 100, 9.5, 1),
        ("F9", 101, 11, 1), ("F10", 109, 12, 1), ("F11", 103, 13, 1), ("F12", 111, 14, 1),
        ("Backquote", 50, 0, 1), ("Digit1", 18, 1, 1), ("Digit2", 19, 2, 1), ("Digit3", 20, 3, 1), ("Digit4", 21, 4, 1),
        ("Digit5", 23, 5, 1), ("Digit6", 22, 6, 1), ("Digit7", 26, 7, 1), ("Digit8", 28, 8, 1), ("Digit9", 25, 9, 1),
        ("Digit0", 29, 10, 1), ("Minus", 27, 11, 1), ("Equal", 24, 12, 1), ("Backspace", 51, 13, 2),
        ("Tab", 48, 0, 1.5), ("KeyQ", 12, 1.5, 1), ("KeyW", 13, 2.5, 1), ("KeyE", 14, 3.5, 1), ("KeyR", 15, 4.5, 1),
        ("KeyT", 17, 5.5, 1), ("KeyY", 16, 6.5, 1), ("KeyU", 32, 7.5, 1), ("KeyI", 34, 8.5, 1), ("KeyO", 31, 9.5, 1),
        ("KeyP", 35, 10.5, 1), ("BracketLeft", 33, 11.5, 1), ("BracketRight", 30, 12.5, 1), ("Backslash", 42, 13.5, 1.5),
        ("CapsLock", 57, 0, 1.75), ("KeyA", 0, 1.75, 1), ("KeyS", 1, 2.75, 1), ("KeyD", 2, 3.75, 1), ("KeyF", 3, 4.75, 1),
        ("KeyG", 5, 5.75, 1), ("KeyH", 4, 6.75, 1), ("KeyJ", 38, 7.75, 1), ("KeyK", 40, 8.75, 1), ("KeyL", 37, 9.75, 1),
        ("Semicolon", 41, 10.75, 1), ("Quote", 39, 11.75, 1), ("Enter", 36, 12.75, 2.25),
        ("ShiftLeft", 56, 0, 2.25), ("KeyZ", 6, 2.25, 1), ("KeyX", 7, 3.25, 1), ("KeyC", 8, 4.25, 1), ("KeyV", 9, 5.25, 1),
        ("KeyB", 11, 6.25, 1), ("KeyN", 45, 7.25, 1), ("KeyM", 46, 8.25, 1), ("Comma", 43, 9.25, 1), ("Period", 47, 10.25, 1),
        ("Slash", 44, 11.25, 1), ("ShiftRight", 60, 12.25, 2.75),
        ("ControlLeft", 59, 0, 1.25), ("AltLeft", 58, 1.25, 1.25), ("MetaLeft", 55, 2.5, 1.25), ("Space", 49, 3.75, 6.25),
        ("MetaRight", 54, 10, 1.25), ("AltRight", 61, 11.25, 1.25), ("Fn", 63, 12.5, 1.25), ("ControlRight", 62, 13.75, 1.25),
        ("Insert", 114, 15.25, 1), ("Home", 115, 16.25, 1), ("PageUp", 116, 17.25, 1),
        ("Delete", 117, 15.25, 1), ("End", 119, 16.25, 1), ("PageDown", 121, 17.25, 1),
        ("ArrowUp", 126, 16.25, 1), ("ArrowLeft", 123, 15.25, 1), ("ArrowDown", 125, 16.25, 1), ("ArrowRight", 124, 17.25, 1),
    ].map { Key(code: $0.0, keyCode: $0.1, x: $0.2, width: $0.3) }

    static let byKeyCode = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) })

    /// Stereo position for a key whose center is `x` units from the board's left edge.
    public static func pan(x: Double) -> Double {
        max(-0.7, min(0.7, (x / boardWidth - 0.5) * 1.4))
    }

    /// Which of `widths` a key sounds like, and where it sits. Keys not on the table (a numeric
    /// keypad, media keys, other layouts' extra keys) sound like a letter in the middle.
    public static func sound(for keyCode: UInt16) -> (widthIndex: Int, pan: Double) {
        guard let key = byKeyCode[keyCode] else { return (0, 0) }
        return (nearestWidthIndex(key.width), key.pan)
    }

    public static func nearestWidthIndex(_ width: Double) -> Int {
        var best = 0
        for (i, w) in widths.enumerated() where abs(w - width) < abs(widths[best] - width) { best = i }
        return best
    }
}
