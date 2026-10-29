# Security

Tonecap plays a sound when a key goes down or comes up in any app, which takes a powerful permission. So it's built to use as little of it as it can: it learns which key moved, never which letter, and keeps nothing.

## Reporting a vulnerability

Please report security problems privately through **Security → Report a vulnerability** on this repository, not in a public issue. You'll get a reply within a few days.

## What Tonecap can access

| | |
|---|---|
| **Input Monitoring** | The one permission it asks for, which you turn on yourself in System Settings → Privacy & Security → Input Monitoring. It's used for one thing only, described below. Without it, the app plays nothing but its own Test button. |
| **The app in front** | Its bundle identifier and name, which macOS tells every app, so it can stay quiet in the apps you pick. |
| **Its own settings** | Your sound, volume, the apps it stays quiet in and its options, in its preferences file. |

### What it uses Input Monitoring for

Tonecap has one listen-only event tap, for key down, key up and modifier-key changes. From each event it reads three things:

1. **The key code,** a number for the physical key (the one in the row above Return, say), used to pick the sound for a key of that size and its place left to right.
2. **Whether it's an auto-repeat,** so a held key doesn't machine-gun unless you ask it to.
3. **The modifier flags,** so it can tell whether a Shift or Command key went down or came up.

Then it plays a sound, and forgets the event. While secure input is on (a password field, or Terminal's Secure Keyboard Entry), it doesn't even do that: every event is dropped unread.

## What it can't access

- **What you type.** It never turns a key into a character: it reads no event's text and uses no keyboard layout. A key code says which key, not which letter, and the same key is a different letter on different layouts. CI checks that the only things read from an event are the key code, the auto-repeat flag and the modifier flags, that nothing that turns keys into characters or copies an event is called, in the source and in the built app.
- **Your keys, beyond listening.** The tap is listen-only, so it can't change, delay or block a key, and Tonecap never posts an event of its own. CI checks the tap is created listen-only, and that the built app imports none of the calls that post events.
- **Password fields.** While secure input is on, as it is in password fields, macOS sends no key presses to any app, and Tonecap drops the modifier-key changes it still sends. A password typed where secure input isn't on, like `sudo` in a terminal without Secure Keyboard Entry, plays like any other typing, though even then Tonecap only learns which keys moved.
- **The internet.** It has no networking code. CI checks the source of every build for networking APIs and for starting other programs, and checks the built app links no networking framework and imports none of those calls. It opens two things, from one file: the Input Monitoring page in System Settings, and the playground at `https://stanczykwyatt.github.io/tonecap/`, with your sound after the `#`, which browsers never send to a server.
- **Your files, the microphone and the screen.** It never opens, reads or writes a file itself (CI checks for every way to): its settings go through macOS's preferences system, and Open at Login through macOS's own login items. It never uses the microphone, and never reads the screen or other apps' windows. It writes to the clipboard only when you click Copy Link, and never reads from it.

Check it yourself on any copy of the app:

```bash
codesign -d --entitlements - /Applications/Tonecap.app
```

It prints no entitlements at all.

## How it handles things

- **Keys are handled on their own thread,** which only looks up a sound and hands it to a player. Nothing is logged, counted or kept. The set of keys being held, which it needs to play a release, is cleared when it stops listening or macOS pauses the tap, and never holds more than 64.
- **Sounds are rendered ahead of time** from your settings, so nothing about a key press is ever written anywhere, even temporarily.
- **Saved settings are read as untrusted.** A value out of range is clamped, an unknown one keeps its default, an app identifier that isn't one is dropped, and names have control characters and invisible text-direction marks removed before they're shown.
- **Links are read strictly.** A pasted link or code must be exactly the right length, version and check byte, with every value in range, or it's refused. Nothing in it is ever run or opened.
- It has no dependencies. Every line that runs is in this repository.

## The playground

The web playground runs entirely in your browser. Its Content-Security-Policy lets it load only its own scripts, styles and images and allows no network connections at all, and CI checks its code never connects, stores anything or builds HTML from text. What you type in the test box stays on the page.

## Why it isn't sandboxed

The App Sandbox is made for apps that keep to themselves. Tonecap's whole job is hearing keys pressed in other apps, which the Mac App Store doesn't allow for this kind of app. So it runs outside it, like other input utilities, with no entitlements at all and the hardened runtime. Outside the sandbox an app needs no entitlement to use the network, so what keeps Tonecap offline is that it has no code to do it, which CI checks in the source and the built app on every build. Releases are built by CI from the tagged source, with the build's code hash attached: compare it with `codesign -dvvv /Applications/Tonecap.app`.

## The signature

Releases are signed ad hoc, not with a paid Apple Developer ID. macOS ties the Input Monitoring permission you grant to that exact build, so no other program can borrow it by claiming to be Tonecap. The catch is that each update counts as a new app: after updating, go to System Settings → Privacy & Security → Input Monitoring, select Tonecap, click –, then open Tonecap and click Allow Input Monitoring… again. A Developer ID signature, which would keep the permission across updates, is planned.
