// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tonecap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tonecap", targets: ["Tonecap"]),
    ],
    targets: [
        // The sound engine (a port of the web one), share codes, the key table, which key events
        // make a sound, and the settings, with nothing tied to the screen, the keyboard or the
        // speakers, so it can all be tested with made-up key events.
        .target(name: "ToneCore"),
        .executableTarget(name: "Tonecap", dependencies: ["ToneCore"]),
        .testTarget(name: "ToneCoreTests", dependencies: ["ToneCore"], exclude: ["Fixtures"]),
        // The app's glue, tested with made-up key events, an audio engine that renders offline
        // instead of to the speakers, and windows that are never shown.
        .testTarget(name: "TonecapTests", dependencies: ["Tonecap", "ToneCore"]),
    ]
)
