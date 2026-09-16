#!/bin/bash
# Builds ScreenRecord.app into ./build and ad-hoc signs it.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="ScreenRecord"
BUNDLE="build/${APP_NAME}.app"
CONFIG="${1:-release}"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"
BINARY=".build/$CONFIG/$APP_NAME"

echo "▸ Assembling bundle…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "▸ Rendering icon…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift Tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Signing…"
# An ad-hoc signature is tied to the binary hash, so macOS drops the granted
# Screen Recording permission on every rebuild. A real certificate keeps it.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application|Mac Developer/ {print $2; exit}')}"
if [ -n "$SIGN_ID" ]; then
    echo "  identity: $SIGN_ID"
    codesign --force --sign "$SIGN_ID" --timestamp=none "$BUNDLE"
else
    echo "  identity: ad-hoc (разрешения будут слетать при каждой пересборке)"
    codesign --force --sign - --timestamp=none "$BUNDLE"
fi

echo "✓ Готово: $(pwd)/$BUNDLE"
