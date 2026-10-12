#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
app="$PWD/build/Prism.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Prism "$app/Contents/MacOS/Prism"
cp scripts/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/build" "$PWD/Assets/Brand/PrismAppIcon.png"
cp Assets/Brand/PrismMark.png "$app/Contents/Resources/PrismMark.png"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/build/Prism-macOS.zip"
(cd build && shasum -a 256 Prism-macOS.zip > SHA256SUMS.txt)
echo "Built $app"
