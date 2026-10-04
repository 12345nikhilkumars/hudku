# Hudku

A tiny, fully native macOS launcher — one hotkey, everything you reach for all day. A stripped,
renamed fork of an upstream AGPL launcher (see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)).

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. Runs as an
accessory app with no Dock icon; summon it from a global hotkey (Settings → General) or via
Spotlight.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit apps.
- **Global hotkeys** — one shortcut summons the palette; per-app hotkeys and a Hyper Key too.
- **Clipboard history** — searchable text/image history, pasted back into the app you were using.
- **Calculator** — math, unit, live currency and crypto conversions inline in the palette.
- **Emoji & symbols** — a searchable grid, plus Slack/Discord-style `:smile` typing in the launcher.
- **Dictionary** — type `def word` in the launcher and the full definition page renders in place.
- **File search** — open files and folders through Spotlight, with no index of our own.
- **Apple Shortcuts** — search and run the shortcuts you built, with aliases and hotkeys.
- **System actions** — lock, sleep, empty trash, toggle appearance, Bluetooth, mute, and more.
- **Camera** — a preview, and a photo straight to the clipboard.
- **Uninstaller** — remove an app with its leftover files.

## Build

Requires macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project Hudku.xcodeproj -scheme Hudku -configuration Release build
```

The optional memory of the original author's docs lives in [docs/](docs/README.md); the harnesses in
[Tests/](Tests) run with `./Scripts/run-tests.sh`.

## License

[AGPL-3.0](LICENSE)
