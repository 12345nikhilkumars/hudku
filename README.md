# Hudku

A tiny, fully native macOS launcher: one hotkey for everything you reach for all day.
A stripped, renamed fork of an upstream AGPL launcher (see [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md)).

SwiftUI and AppKit, zero third-party dependencies, no Electron, no telemetry. Runs as an
accessory app with no Dock icon; summon it from a global hotkey (Settings > General) or
Spotlight. Builds are ad-hoc signed for local use.

## Features

- **App launcher**: fuzzy search, favorites, running state, quit and restart.
- **Global hotkeys**: one shortcut summons the palette; per-app hotkeys and a Hyper Key too.
- **Clipboard history**: searchable text and image history, pasted back into the app you were using.
- **Calculator**: math, units, and live currency and crypto conversions, inline in the palette.
- **Emoji & symbols**: a searchable grid, plus Slack/Discord-style `:smile` typing in the launcher.
- **Dictionary**: type `def word` and the full definition page renders in place.
- **File search**: type `@name` or `?name` in the launcher and files and folders from your home
  appear as you type. The `Search Files` fallback opens the full screen, with previews.
- **Apple Shortcuts**: search and run the shortcuts you built, with aliases and hotkeys.
- **System actions**: lock, sleep, empty trash, toggle appearance, Bluetooth, mute, and more.
- **Camera**: a preview, and a photo straight to the clipboard.
- **Uninstaller**: remove an app with its leftover files.

## Build

Requires macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project Hudku.xcodeproj -scheme Hudku -configuration Release -derivedDataPath build build
```

Install: quit any running copy, copy `build/Build/Products/Release/Hudku.app` to `/Applications`,
then `open` it.

## Development

- Tests: `./Scripts/run-tests.sh` (standalone Swift harnesses; there is no XCTest target).
- Architecture, conventions, and invariants: [AGENTS.md](AGENTS.md).
- Performance profile and the `HUDKU_PERF` harness: [PERFORMANCE.md](PERFORMANCE.md).
- The upstream author's reference docs: [docs/](docs/README.md).

## License

AGPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
