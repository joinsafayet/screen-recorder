#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos15.0" \
  Sources/Prism/Models.swift Sources/Prism/RegionSelector.swift Sources/Prism/CaptureEngine.swift \
  Sources/Prism/LibraryStore.swift Sources/Prism/AudioMixer.swift Sources/Prism/VideoExporter.swift Tests/Verification.swift Tests/Performance.swift Tests/LiveCapture.swift Tests/LibraryVerification.swift -o build/PrismVerifier
build/PrismVerifier "$@"
