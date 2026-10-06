**Install (DMG)**: download the DMG below, open it, and drag Hudku into Applications. The
build is ad-hoc signed and not notarized, so macOS may block the first launch: right-click the
app and choose Open, or clear the quarantine flag:

```sh
xattr -d com.apple.quarantine /Applications/Hudku.app
```

**Install (Homebrew)**:

```sh
brew tap 12345nikhilkumars/tap
brew install --cask hudku
```

**Build from source** and the rest of the docs: [README](../README.md) and [docs](../docs/README.md).
