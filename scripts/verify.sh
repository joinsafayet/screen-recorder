#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
sources=(Sources/Prism/*.swift)
sources=(${sources:#*PrismApp.swift})
swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos15.0" "${sources[@]}" \
  Tests/Verification.swift Tests/Performance.swift Tests/LiveCapture.swift Tests/LibraryVerification.swift Tests/ExtendedVerification.swift -o build/PrismVerifier
build/PrismVerifier "$@"
