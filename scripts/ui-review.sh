#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/PrismUIReview.app/Contents/MacOS
sources=(Sources/Prism/*.swift)
sources=(${sources:#*PrismApp.swift})
swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos15.0" "${sources[@]}" Tests/UIReview.swift -o build/PrismUIReview.app/Contents/MacOS/PrismUIReview
cat > build/PrismUIReview.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>PrismUIReview</string>
<key>CFBundleIdentifier</key><string>com.prism.ui-review</string>
<key>CFBundleExecutable</key><string>PrismUIReview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - build/PrismUIReview.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/PrismUIReview.app
