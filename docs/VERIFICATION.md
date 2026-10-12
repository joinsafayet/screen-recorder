# Prism 3 verification

Release checks were performed on 2026-10-12 with macOS 27.0.1 (26A434), Apple Silicon, and Swift 6.4 command-line tools. Tests use temporary libraries, generated media, and the verifier's own window. User recordings and system privacy settings are not modified.

## Automated media and persistence

`scripts/verify.sh --long-live-benchmark` passed all 26 functional/media checks. The native benchmark was explicitly skipped because the desktop was locked.

Coverage includes region move/resize/aspect/screen bounds, area selection retry/release/cancellation, saved areas, preparation estimates/meters, settings migration, pause removal, static-screen tails, empty recording failures, synthetic camera composition/HEVC, two-source audio mixing, compressed-video packet preservation, trim/export, active cancellation, destination preservation, index rollback/recovery, and journal ordering.

An abruptly exiting child process writes timestamped media without finalizing its writer. Completed fragments in both MOV and MP4 decoded and recovered into the library with the saved title and valid markers. This verifies completed-fragment recovery; it cannot preserve an unwritten or incomplete fragment.

Timeline verification creates real two-section square exports, checks dimensions and duration, decodes video and audio, and measures reduced audio levels at both fade ends. Saved edits survive reload, source bytes remain identical, and cancelled exports leave an existing target unchanged. Presentation checks inspect rendered arrow pixels, pointer interpolation, plain-key filtering, and SRT remapping across cuts. Library checks cover project/tag/favorite persistence and loading 1,000 pointer samples from a separate sidecar. Queue checks verify capture priority, completion, persisted edit snapshots, and original-file protection.

Full output: `build/Prism3-final-verification.log`.

## Sustained encoding

`scripts/verify.sh --soak` passed a 60-second paced 3840 × 2160 / 60 fps profile with synthetic presenter composition and two synthetic PCM streams.

| Measurement | Result |
| --- | --- |
| Attempted / saved source frames | 3,600 / 3,600 |
| Dropped video / audio buffers | 0 / 0 |
| Mean / peak frame processing | 4.49 / 9.77 ms |
| Largest encoded timestamp gap | 16.67 ms |
| Capture wall time | 59.99 s |
| Peak resident memory | 128.05 MB |
| Audio finalization mix | 0.27 s |

The encoded stream includes static-tail checkpoints, so encoded packet count can exceed the source frame count. This profile verifies encoder/compositor throughput. It excludes WindowServer, physical devices, visible UI animation, and competing user workloads; it does not establish universal zero-lag capture.

Evidence: `build/soak-verification.log` and `build/Soak-performance-report.json`.

## Interface review

The isolated UI review host rendered Prism's owned views at 1240 × 860 and 940 × 680, plus the 1060 × 730 editor and light appearance. These renders were visually inspected. Compact studio controls now fit, settings use a dedicated compact panel, preferences stack vertically, batch actions occupy two rows, and capture metrics reflow. Blue, teal, amber, and coral palettes share the dark/light design. Motion is state-driven and respects Reduce Motion.

A 120-action run cycled individual tab, source mode, frame rate, accent, motion, and theme changes with owned-view layout requests. It completed without a stalled main actor. Mean mutation/layout time was 39.34 ms, with a 92.81 ms maximum; mean action interval was 97.63 ms including the requested 55 ms delay. Because the desktop was locked, these measurements do not establish displayed frame rate or the feel of physical clicks. The native AVPlayer surface is blank in locked/offscreen renders; actual export/video decoding passed separately.

Evidence: `build/Prism3-render-*.png`, `build/Prism3-compact-*.png`, `build/Interaction-performance-report.json`.

## Package

`scripts/build.sh` built Prism 3.0.0 (bundle build 4), the arm64 executable, icon, and `build/Prism-macOS.zip`. `codesign --verify --deep --strict` and `plutil -lint` passed. The ZIP contains the expected version and application executable. Command-line tools emitted linker search-path warnings for missing developer directories; the build succeeded.

This package uses ad-hoc local signing. Developer ID signing and notarization require the owner's release credentials.

## Remaining device checks

The final session's desktop was locked. The long live benchmark reported **SKIP**, not PASS. It can be rerun with `scripts/verify.sh --long-live-benchmark` after unlocking and making screen access available to the terminal host. Native source picker/region GUI interaction, visible tab/button animation, physical microphone/camera capture and unplugging, and local speech/keyboard permission flows still require an unlocked device with the relevant permissions and hardware. Manual captions and their exported timings were checked independently.
