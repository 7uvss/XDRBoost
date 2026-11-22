#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/XDRBoost.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Source/*.swift -o "$APP/Contents/MacOS/XDRBoost" -framework AppKit -framework MetalKit
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP"
