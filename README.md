# Hudku (ಹುಡ್ಕು)

Find → apps, files, emoji, clipboard  
Do → calculations, conversions, uninstall, trash  
Done → disappear and get out of the way

A tiny, fully native macOS launcher: one hotkey for everything you reach for all day.

Hudku started as a fork of [Tinycast](https://github.com/abue-ammar/tinycast) and kept the
native launcher core from that starting point, reworked for one simpler brief. What drove the
fork: an AI assistant bundled into an app launcher, day-to-day conveniences quietly sitting on
hundreds of megabytes of RAM, searches that answered in milliseconds, and small paper cuts in
the everyday flows. Everything here was ported to that leaner brief. See [LICENSE](LICENSE)
and [NOTICE.md](NOTICE.md) for the fork's licensing.

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
  appear as you type, served by Hudku's own name index rather than Spotlight.
- **Apple Shortcuts**: search and run the shortcuts you built, with aliases and hotkeys.
- **System actions**: lock, sleep, empty trash, toggle appearance, Bluetooth, mute, and more.
- **Camera**: a preview, and a photo straight to the clipboard.
- **Uninstaller**: remove an app with its leftover files.

## Performance

**Device**: MacBook Pro (Mac16,8, Apple M4 Pro, 24 GB), macOS 27.0. All three launchers
installed side by side and measured the same way: quit, launch fresh, summon the surface, then
sum the whole process suite (main process plus XPC services and helpers) over a 60 s window.
Three runs per open state, medians shown; full method, flame graphs, and the memory ladder:
[PERFORMANCE.md](PERFORMANCE.md).

| | Hudku 0.0.2 | Tinycast 0.11.3 | Raycast 2.6.2 |
| --- | --- | --- | --- |
| Processes | 1 | 1 | 4 (up to 8 seen) |
| RAM, closed / open | **22 MB / 38 MB** | 33 MB / 45 MB | 272 MB / 287 MB |
| CPU, open (60 s) | **0.04 s** | 0.02 s | 0.80 s |
| Energy impact, open (top) | **~0.02** | 0.00 | ~1.1 |
| Threads, open | 3 | 4 | 82 |

### Command speeds

Engine numbers are pure computation from the same harness compiled into both codebases; Raycast
has no such instrument, so its column is the whole input-to-result path, measured externally
with real key events and the Accessibility API (a few ms resolution). Raycast answers every
command in roughly 7 to 15 ms end to end.

| Command | Hudku 0.0.2 (engine) | Tinycast 0.11.3 (engine) | Raycast 2.6.2 (input to result) |
| --- | --- | --- | --- |
| App search, median query p50 / p90 | **12.4 / 34.2 µs** | 108 / 167 µs | 13 ms (p50) |
| Single letter / full app name | **7.9 / 5.3 µs** | 304 / 86 µs | ~7 - 15 ms across root queries |
| Empty query (default list) | **298 µs** | 525 µs | n/a |
| Calculator, units, currency | **1.9 - 11.8 µs** | 1.2 - 11.8 µs | 14.6 ms |
| Color (`#ff5733`) | **5.0 µs** | 87.8 µs | 12.8 ms |
| Emoji engine call | **0.33 µs** | 3.05 ms | 13.7 ms (Search Emoji) |
| Dictionary lookup | **4.6 ms cold / 7.5 µs repeat** | 8.1 ms | 12.3 ms (Define Word) |
| File search | **0.03 - 7 ms** (inline `@`, Hudku's own index) | 53.2 ms (Spotlight, screen) | 12.5 ms (Search Files) |
| Clipboard filter | 58 µs | **31 µs** | n/a (no public search) |
| External CPU per typed query | **0.00 - 0.01 s** | 0.04 - 0.09 s | not measurable (backend never idles) |

Raycast's four processes (its Node backend dominates at 195-245 MB) start at 272 MB, and the
backend runs whether the window is up or not; a fuller state on this Mac showed 8 processes and
about 510 MB. Tinycast's file-search screen pulls in a QuickLook helper when results are
browsed (about 90 MB suite total on a quick lookup, up to roughly 430 MB after previewing
several files); Hudku answers `@word` inline from its own name index and never leaves its
~47 MB plus the index's ~5 MB once file search is first used. Emoji and dictionary
are invoked differently in each launcher (Hudku inline as `:smile` and `def word`; Tinycast
through a separate Emoji screen and a Define Word row; Raycast through its own commands), so
those rows compare engines and service calls, not keystroke flows.

## Install

### DMG

Download `Hudku-0.0.2.dmg` from the
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
- Docs: [docs/](docs/README.md) covers the launcher, file search, settings, permissions,
  standards, and the build and release pipeline.
- Performance profile and the `HUDKU_PERF` harness: [PERFORMANCE.md](PERFORMANCE.md).

## License

AGPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
