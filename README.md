# Hudku (ಹುಡ್ಕು)

Find → apps, files, emoji, clipboard  
Do → calculations, conversions, uninstall, trash  
Done → disappear and get out of the way

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

## Performance

Measured on a MacBook Pro (Mac16,8, Apple M4 Pro, 24 GB) running macOS 27.0, with all three
launchers installed side by side and left untouched under the same protocol:

| | Hudku 0.0.1 | Tinycast 0.11.3 | Raycast 2.6.2 |
| --- | --- | --- | --- |
| Idle RAM | **22 MB** | 33 MB | 44 MB |
| Idle CPU (per 60 s) | 0.05 s | 0.03 s | 0.70 s (first-run onboarding live) |
| Threads | 3 | 3 | 28 |
| Palette search, p50 | **13.8 µs** | not externally measurable | not externally measurable |
| Emoji search, typing p50 (same `-O` benchmark, both codebases) | **0.29 ms** | 3.94 ms | n/a |

A full Settings browse peaks around 107 MB, nothing is retained after close, and idle is a flat
22 MB with no Dock icon and no menu-bar item. The full profile, method, and flame graphs live in
[PERFORMANCE.md](PERFORMANCE.md).

## Install

### DMG

Download `Hudku-0.0.1.dmg` from the
[latest release](https://github.com/12345nikhilkumars/hudku/releases), open it, and drag Hudku
into Applications. The build is ad-hoc signed and not notarized, so macOS may block the first
launch: right-click the app and choose Open, or clear the quarantine flag yourself:

```sh
xattr -d com.apple.quarantine /Applications/Hudku.app
```

### Homebrew

```sh
brew tap 12345nikhilkumars/tap
brew install --cask hudku
```

## Build from source

Requires the full Xcode (26 or later) from the Mac App Store, not just the Command Line Tools
(the project uses SwiftUI macros), plus [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Hudku.xcodeproj -scheme Hudku -configuration Release -derivedDataPath build build
```

The app lands in `build/Build/Products/Release/Hudku.app`. If `xcode-select` points at the
Command Line Tools, prefix the build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
or run `sudo xcode-select -s /Applications/Xcode.app` once.

## Development

- Tests: `./Scripts/run-tests.sh` (standalone Swift harnesses; there is no XCTest target).
- Architecture, conventions, and invariants: [docs/architecture.md](docs/architecture.md) and
  [docs/standards.md](docs/standards.md).
- Performance profile and the `HUDKU_PERF` harness: [PERFORMANCE.md](PERFORMANCE.md).
- The upstream author's reference docs: [docs/](docs/README.md).

## License

AGPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
