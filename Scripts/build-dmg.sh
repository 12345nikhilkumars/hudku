#!/bin/bash
# Build a signed Hudku.app into build/Hudku-<version>.dmg. Usage: ./Scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Hudku Self-Signed"
DERIVED="build/DerivedData"

SIGN_FLAGS=()
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "▸ Building signed Hudku.app (Release)…"
    SIGN_FLAGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none")
else
    echo "▸ Building ad-hoc Hudku.app (Release)…"
fi

xcodebuild -project Hudku.xcodeproj -scheme Hudku -configuration Release \
    -derivedDataPath "$DERIVED" \
    ${SIGN_FLAGS+"${SIGN_FLAGS[@]}"} \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Hudku.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Hudku-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Hudku" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"