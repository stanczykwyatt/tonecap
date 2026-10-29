# Contributing

Thanks for helping out! Bug reports, ideas, sound suggestions and pull requests are all welcome.

## Saying a sound is wrong

The most useful report is a build and a sentence: "this link, and the brass plate sounds like a bell, it should be lower and shorter". Copy the link from the playground or from the app's Share tab, and post it in [Discussions](https://github.com/stanczykwyatt/tonecap/discussions). Please don't attach recordings of keyboards: this project contains no recorded sound, and won't take any.

## Getting started

You need Node 20 or later for the engine, and macOS 14 or later with Swift 6 (Xcode 16 or the Command Line Tools) for the app.

```bash
node --test test/                 # the engine's tests
node scripts/analyze.mjs          # how each preset's sound is spread across the spectrum
swift test                        # the Swift port, the app's glue and its panel
scripts/build-app.sh              # build Tonecap.app into ./build
```

To try the playground, serve `docs/` with any static server (module scripts don't load from `file://`), for example `python3 -m http.server -d docs`.

## How the sound is made

`docs/engine/tonecap.js` is the engine. A press is a handful of events in time:

- **the stem scraping its housing** as it travels, a burst of filtered noise that lube turns down;
- **a tactile bump** partway down, or **a click**: a very short, hard pulse into a few high resonators, a little before the bottom;
- **the bottom-out**, a pulse whose length is how soft the hit is: a hard one is short and reaches high resonances, a soft one is long and only reaches low ones;
- **on wide keys, the stabilizer wires** knocking a millisecond or two later, unless they're tuned;
- **and for a release, the top-out**, quieter and a little higher.

Each pulse rings banks of two-pole resonators, each set by a frequency, a ring time and a level: the keycap (pitch from material, thickness, profile and width), the plate (pitch, ring and level per material, foam shortening the ring), the case (a low body mode and its overtone, plus a ping for aluminum, foam damping both), the desk, the spring (a faint metallic ring that lube removes) and the stabilizers. Then a gentle high-pass and a short fade.

The numbers were tuned by measuring, not by copying: `scripts/analyze.mjs` prints each preset's spectral centroid and the share of energy below 1 kHz and above 4 kHz, and the tests in `test/engine.test.js` hold the sound to how builds are usually described (thocky builds deeper than clacky ones, a click bright and before the bottom-out, foam shortening the ring, a release quieter than a press, and so on). If you change the model, keep those tests passing, and say in the pull request what you listened to.

Every random choice comes from a seed made from the design, the key's width, the variant and whether it's a press or release, using only 32-bit integer steps, so the same inputs always give the same samples.

## The Swift port, and keeping the two the same

`Sources/ToneCore/Engine.swift` is a line-by-line port of the engine, with the same names, steps and order, so the Mac app and the browser make the same sound. To keep them in step:

1. Change `docs/engine/tonecap.js` first.
2. Make the same change in `Engine.swift` (and `Design.swift` or `Keyboard.swift` for presets, codes or the key table).
3. Run `node scripts/make-fixtures.mjs`, which renders a spread of presets, key sizes, presses and releases at 16, 22.05, 44.1 and 48 kHz into `Tests/ToneCoreTests/Fixtures/engine.json` (every fourth sample, to keep the file small), with the share codes, seeds and key table.
4. Run `swift test`. `EngineTests` renders the same cases in Swift and fails if any stored sample differs by more than 0.00002. The only differences should come from the two math libraries' `sin`, `cos` and `exp`.

CI fails if the fixtures are out of date, so a change to one side can't slip in alone.

## The app

The menu bar app is in `Sources/Tonecap`. Deciding which key events make a sound, the key table, the settings and the share codes live in `Sources/ToneCore`, tested with made-up key events. `KeyListener.swift` is the only file that listens to keys, `Player.swift` the only one that plays sound, `Links.swift` the only one that opens anything or uses the clipboard.

No test listens to your keys, posts an event, plays through your speakers or puts a window on screen: the player is tested with an audio engine that renders into memory, and the panel is rendered from windows that are never shown. To redraw the art: `SCREENSHOT_DIR=docs swift test --filter Window`, then `swift scripts/make-icon.swift` and `swift scripts/make-art.swift`.

## Ground rules

- **No recordings.** Every sound comes from the code. No samples, impulse responses or sound packs, from anywhere.
- **No network access, ever,** in the app or the playground. Pull requests that add networking, analytics or update checks won't be merged.
- **Key codes only.** Never read characters, text or the keyboard layout, and never post, change or block an event.
- **Least access.** No entitlements, and no new permissions without a very good reason.
- **No new dependencies** without a very good reason. There are none today, in Swift or npm.
- **Generic preset names** that describe a sound, never a product's name.
- Run `node --test test/` and `swift test` before opening a pull request.
- Keep commits small, with a short message saying what changed and why.

## Security issues

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
