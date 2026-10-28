#!/bin/bash
# Builds 곁메모 for macOS: mac/dist/곁메모.app and mac/dist/GyeotMemo-v<version>-mac.dmg
# Requires the Xcode Command Line Tools (xcode-select --install). No other dependencies.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DIST=dist
BUILD=$DIST/build
APP="$DIST/곁메모.app"
DMG="$DIST/GyeotMemo-v$VERSION-mac.dmg"
rm -rf "$BUILD" "$APP" "$DMG"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary (Apple silicon + Intel), macOS 13 or later.
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "$BUILD/GyeotMemo-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/GyeotMemo" "$BUILD/GyeotMemo-arm64" "$BUILD/GyeotMemo-x86_64"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swift make-icon.swift "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

# Ad-hoc signature: required to run on Apple silicon. Not notarized (no Developer ID).
codesign --force --sign - --timestamp=none "$APP"

if [ "${1:-}" != "--no-dmg" ]; then
    STAGE="$BUILD/dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "곁메모 $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
    echo "$DMG"
fi
echo "$APP"
