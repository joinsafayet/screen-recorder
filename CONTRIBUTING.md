# Contributing to Prism

Prism is a native macOS 15+ app written in Swift 5 language mode with Swift 6 tooling. The downloadable package is built for Apple Silicon. Keep changes focused on a concrete workflow and preserve recording originals, edit documents, and library metadata.

## Local development

```sh
swift build -c release
scripts/build.sh
scripts/verify.sh
```

The verification script compiles its own generated-media harness. It does not require live screen/audio/camera permissions. Build outputs are ignored by Git. Use `scripts/ui-review.sh` to build an isolated preview host; it creates a sample recording automatically. Launch that host with `--render --docs` for documentation media or `--render` for owned-view images and the interaction report. Its library is separate from the normal Prism library.

## Relevant checks

| Change | Verification |
| --- | --- |
| Capture, audio, recovery, persistence, or timeline | `scripts/verify.sh` |
| Encoder/compositor throughput | `scripts/verify.sh --benchmark` or `--soak` |
| Live ScreenCaptureKit pipeline | `--live-benchmark` or `--long-live-benchmark` on an unlocked Mac |
| Native interface | Dark/light, 940 × 680 and 1240 × 860 layouts, keyboard focus, Reduce Motion |
| App packaging | `scripts/build.sh`, `codesign --verify --deep --strict build/Prism.app`, ZIP checksum |

Use the repository's verification commands rather than `swift test`: this project uses a standalone media harness. Report **SKIP** for unavailable device/permission checks, and include the actual result of checks you ran. Do not present synthetic encoder tests as proof of live desktop frame rate.

## Design conventions

Use the shared colors, button feedback, motion preferences, and optical icon grid. Keep animation tied to a user action or live operation. New recording controls must remain responsive during capture; put decoding, transcription, disk work, and encoding on the existing background paths. Respect both the app's Interface motion option and macOS Reduce Motion.

## Pull requests

Describe the concrete problem, resulting behavior, and validation. Include interface previews for visual changes and state any device-level checks that remain. The PR template provides a short structure.

## Release preparation

1. Update `scripts/Info.plist` and the fallback version/build in `AboutView.swift`, then add the release to `CHANGELOG.md`.
2. Run the relevant media, native-device, and packaging checks. Review [verification](docs/VERIFICATION.md) for their scope.
3. Confirm the app ZIP, checksum file, version, architecture, and signature. Developer ID signing/notarization requires the owner's signing credentials.
4. Commit and push the validated source, then tag that exact commit and attach the app archive/checksum to the release. Label development builds as previews.

CI uses the [standard macOS 26 Apple Silicon runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), with official checkout/artifact actions pinned to commit SHAs. Its default checks need no device permissions. Benchmark and live-capture modes are local checks.
