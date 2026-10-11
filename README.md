# Prism 2.1 — Screen Studio

A native macOS screen recorder with a polished SwiftUI studio, ScreenCaptureKit capture, accelerated video encoding, and local storage. Requires macOS 15 or later. This build is for Apple Silicon.

## Run

Open **build/Prism.app** in Finder, or unpack **build/Prism-macOS.zip**. Use **Set up recording** to grant Screen Recording access. Allow microphone/camera access when using those devices. macOS may require restarting Prism after changing screen permissions. The app is signed locally for development and is not notarized.

## Recording

- Entire display, individual window, or drag-selected region; multiple displays and Retina resolution.
- Everyday, Tutorial, Smooth motion, and Detail presets, with individual quality and frame-rate controls.
- 720p, 1080p, 4K, and native resolution; 24/30/60 fps. Small sources are never enlarged.
- H.264, HEVC, or automatic codec selection; MP4 and MOV.
- System audio and microphone capture, device selection, and adjustable levels when both are mixed.
- Presenter bubble with four corner positions, adjustable size, and mirroring. It keeps updating over a static screen.
- Cursor visibility and native click highlights for tutorials.
- Session naming, countdown/cancel, pause/resume, timed stop, floating controls, and menu-bar controls.
- Timestamped markers during a recording, with marker navigation and CSV export in the player.
- Capture monitor with saved frames, encoder drops, audio drops, dimensions, and average frame-processing time.
- Free-space check before recording, low-space stop, and prevention of App Nap/display sleep during capture.

Global shortcuts can be enabled in Preferences and work from other apps:

| Action | Global | With Prism focused |
| --- | --- | --- |
| Start / stop | Control Command R | Command Shift R |
| Pause / resume | Control Command P | Command Shift P |
| Add marker | Control Command M | Command Shift M |
| Library | — | Command L |
| Preferences | — | Command comma |

Prism reports conflicts if another application has registered a global shortcut. No Accessibility permission is needed for these hotkeys.

## Library and export

Play, search, favorite, rename, sort by date/name/duration/size, import, reveal in Finder, and move clips to Trash. Thumbnails are decoded away from the UI thread and cached with a memory limit. Imports and save-folder moves run in the background.

The player provides trim sliders, exact in/out values in seconds, selection preview, marker navigation, native sharing, and MP4/MOV export. Select original quality, high quality, 1080p, or a smaller 720p export. Exports show progress, support cancellation, preserve the source, and replace an existing destination only after success. Original-quality exports without trimming copy the encoded video without re-encoding; exact trims are re-encoded.

**Recover recordings**, in the library’s options menu, indexes playable files left after interrupted finalization or a damaged index. Unreadable files are preserved. A damaged index is backed up before it can be replaced. Recovery cannot repair an MP4 whose media writer was interrupted before finalization.

Videos default to `~/Movies/Prism`. Metadata, markers, and thumbnails live in `~/Library/Application Support/Prism`. No accounts or network services are required. Dark, light, and system themes are available.

## Interface and selection

The graphite and blue theme includes light and system variants. Navigation and frame-rate indicators slide between selections; cards, hover states, button presses, changing symbols, countdown digits, presenter options, and the trim panel use short, interruptible transitions. Tabs preserve their scroll positions. Outgoing pages stop accepting input immediately. Turn off **Interface motion** in Preferences for instant feedback; your Mac’s Reduce Motion setting also disables these animations.

Custom buttons accept clicks across their full shape, including empty space in cards. Presets update their settings together and recognize equivalent automatic codecs. Source changes invalidate old preview requests and use a brief debounce. Region selection uses the final release position, clamps to the display, allows retrying a small drag, and cancels once with Escape.

## Performance design

ScreenCaptureKit keeps a queue of three frames. Captures without presenter effects or click highlights use YCbCr buffers directly; presenter composition uses Core Image with a cached mask and a bounded pixel-buffer pool. Encoding requests hardware acceleration and disables frame reordering. Hardware availability still depends on the Mac and selected codec/resolution.

Screen, camera, and audio buffers are handled on a serial media queue. UI meters are throttled, the clock updates once per second, and recording telemetry is observed only by the recording controls. Two-source finalization mixes audio while copying compressed video packets, avoiding another video encode.

The source preview is a snapshot. The capture monitor measures frames received by Prism and encoder backpressure; a static desktop naturally produces fewer frames. Processing time excludes asynchronous encoding. High frame rate, native resolution, other heavy applications, slow disks, and physical devices can affect results; no universal zero-lag guarantee is possible.

## Build and verify

Apple’s command-line developer tools are sufficient. No third-party dependencies are required.

```sh
scripts/build.sh
scripts/verify.sh
scripts/verify.sh --benchmark
scripts/verify.sh --soak
scripts/verify.sh --live-benchmark
```

The 16 functional checks cover actual decoded media, persistence, and selection: pause removal, static tail duration, presenter updates/position, HEVC, audio audibility, exact preservation of compressed video packets after mixing, trim/export, cancellation preserving an existing destination, settings migration, marker persistence, index recovery, rollback after failed index writes, preset matching, region bounds, and retry/release/cancellation events.

`--benchmark` runs four paced six-second 1080p/4K 60 fps profiles, with/without synthetic presenter frames. `--soak` runs a 60-second 4K/60 profile with presenter composition and two synthetic audio streams. Reports record dropped frames, processing times, frame gaps, and resident memory in `build/Performance-report.json` and `build/Soak-performance-report.json`.

`--live-benchmark` creates an animated native window in the background and records only that verifier window for ten seconds through ScreenCaptureKit. It saves `build/Prism-live-1080p60.mp4` and `build/Live-performance-report.json`. Screen access must already be available to the terminal host. Physical microphone and camera capture still require device-level checks after permission is granted.

With Prism running:

```sh
scripts/verify.sh --capture-smoke
```

This captures only Prism’s window, checks pause/resume and decodability, and writes `build/Prism-smoke.mp4`. Tests do not grant permissions or modify system privacy settings. The library tests use temporary folders. `scripts/ui-review.sh` creates a separate GUI review host with an isolated library for visual verification.
