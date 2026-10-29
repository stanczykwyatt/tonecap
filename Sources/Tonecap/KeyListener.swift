@preconcurrency import CoreGraphics
import Carbon.HIToolbox
import Foundation
import ToneCore

/// Hears key presses and releases anywhere, through a listen-only event tap, which needs Input
/// Monitoring. From each event it reads three things: the key code (which key, not which
/// character), whether it's an auto-repeat, and the modifier flags. It never reads characters, can't
/// change or block an event, and keeps nothing. While secure input is on (a password field, or
/// Terminal's Secure Keyboard Entry), it plays nothing, not even modifier keys.
///
/// The tap runs on its own thread, so a busy main thread never delays a sound.
final class KeyListener: @unchecked Sendable {
    private let handler: @Sendable (KeyEvent) -> Void
    private let reset: @Sendable () -> Void
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    /// - Parameter reset: called when the listener may have missed events (macOS paused the tap),
    ///   so keys it thinks are held should be forgotten.
    init(handler: @escaping @Sendable (KeyEvent) -> Void, reset: @escaping @Sendable () -> Void = {}) {
        self.handler = handler
        self.reset = reset
    }

    /// Whether Input Monitoring is on for Tonecap.
    static var hasAccess: Bool { CGPreflightListenEventAccess() }

    /// Shows macOS's own prompt, which adds Tonecap to Privacy & Security → Input Monitoring.
    static func ask() { _ = CGRequestListenEventAccess() }

    private var port: CFMachPort? { lock.withLock { tap } }

    /// Whether the tap exists and macOS still has it turned on. It turns taps off when Input
    /// Monitoring is switched off.
    var isRunning: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Starts listening. False if macOS refused, which means Input Monitoring is off.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        // The tap keeps its own reference to this listener for as long as its thread runs.
        let retained = Unmanaged.passRetained(self)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: KeyListener.callback, userInfo: retained.toOpaque()
        ) else {
            retained.release()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CFMachPortInvalidate(port)
            retained.release()
            return false
        }
        lock.withLock { tap = port }
        let started = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            lock.withLock { runLoop = CFRunLoopGetCurrent() }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            started.signal()
            CFRunLoopRun()
            retained.release()
        }
        thread.name = "Tonecap keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        return true
    }

    func stop() {
        let (port, loop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer { tap = nil; runLoop = nil }
            return (tap, runLoop)
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let loop { CFRunLoopStop(loop) }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let listener = Unmanaged<KeyListener>.fromOpaque(refcon).takeUnretainedValue()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off. Turn it back on, and forget held keys, since releases
            // may have been missed meanwhile.
            listener.reset()
            if let port = listener.port { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown, .keyUp, .flagsChanged:
            // Silent while a password field (or anything else) has secure input on.
            if IsSecureEventInputEnabled() { break }
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            listener.handler(KeyListener.keyEvent(type: type, keyCode: keyCode, isRepeat: isRepeat, flags: event.flags.rawValue))
        default:
            break
        }
        // Listen-only: the event goes on unchanged whatever is returned.
        return Unmanaged.passUnretained(event)
    }

    static func keyEvent(type: CGEventType, keyCode: UInt16, isRepeat: Bool, flags: UInt64) -> KeyEvent {
        switch type {
        case .keyDown: .down(keyCode: keyCode, isRepeat: isRepeat)
        case .keyUp: .up(keyCode: keyCode)
        default: .flagsChanged(keyCode: keyCode, flags: flags)
        }
    }
}
