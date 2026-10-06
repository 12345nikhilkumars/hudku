# Building and releases

## From source

Needs the full Xcode (a recent major version) and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Hudku.xcodeproj -scheme Hudku -configuration Release -derivedDataPath build build
```

The app lands in `build/Build/Products/Release/Hudku.app`. If `xcode-select` points at the
Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Tests

`./Scripts/run-tests.sh` builds and runs the standalone Swift harnesses in `Tests/`. Each
harness compiles the pure Model/Service layer it exercises (the `run <name> <sources>` lines
in the script), so a harness that stops compiling means a decision leaked out of a pure layer.
`Tests/*-performance.swift` cover the hot paths.

## Installing a build

DMG from the release page, drag to Applications. The build is ad-hoc signed and not notarized,
so macOS may block the first launch: right-click the app and choose Open, or run

```sh
xattr -d com.apple.quarantine /Applications/Hudku.app
```

Homebrew: `brew tap 12345nikhilkumars/tap && brew install --cask hudku`.

`Scripts/build-dmg.sh` packages a local `build/Hudku-<version>.dmg`; it uses the "Hudku
Self-Signed" identity when one exists and ad-hoc signing otherwise.

## The pipeline

1. Bump `MARKETING_VERSION` in `project.yml`, then tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
2. The `Release` workflow (`.github/workflows/release.yml`) builds the DMG on a macOS runner
   and publishes the GitHub release. Tags carrying a hyphen (`v0.1.0-rc.1`) publish as
   pre-releases.
3. The Homebrew tap polls for new releases every 15 minutes and bumps `Casks/hudku.rb`
   (version + sha256) automatically; run the tap's `Update cask` workflow manually for an
   instant bump.

## Formatting and linting

`./Scripts/format.sh` (swift-format) and `./Scripts/lint.sh` (SwiftLint) own the style;
the SwiftLint configuration is `.swiftlint.yml`.
