# Prism 3 — Screen Studio

A native macOS recording studio with adjustable capture areas, a non-destructive editor, presentation tools, and a local recording library. Built with SwiftUI, ScreenCaptureKit, Core Image, and AVFoundation. Requires macOS 15 or later; the supplied package targets Apple Silicon.

## Run

Open **build/Prism.app** in Finder, or unpack **build/Prism-macOS.zip**. Use **Choose with macOS** to select a source through the system picker, or **Set up recording** for screen access. Grant microphone/camera access when those devices are enabled. macOS may require restarting Prism after changing screen permissions. The package is signed locally for development; it is not notarized.

## Recording studio

- Resizable sidebar and recording inspector, a larger source preview, and a compact layout with settings in a separate panel.
- Dark, light, and system appearances with blue, teal, amber, and coral accents. Short, interruptible selection and button animations respect Reduce Motion and the Interface motion preference.
- Entire displays, windows, or custom areas, including the native macOS source picker. Area selection supports moving, eight resize handles, aspect ratios, arrow-key nudging, Enter/Escape, and saved areas.
- Everyday, Tutorial, Smooth motion, and Detail presets. 720p, 1080p, 4K, and native resolution; 24/30/60 fps; H.264/HEVC; MP4/MOV. Small sources are never enlarged.
- System audio and selected microphone, with mixing levels. A mirrored presenter bubble supports adjustable size and four positions.
- Opt-in preparation preview with actual camera frames, microphone/system meters, storage estimates, and a five-second test take.
- Session titles, countdown cancellation, pause/resume, timed stop, markers, floating controls, and menu-bar controls. For system-picked display capture, Prism hides its windows and uses the menu bar.
- Capture telemetry shows saved frames, encoder/audio drops, dimensions, and processing time. Background disk checks, low-space stops, and device/display loss handling preserve the take.
- Ten-second movie fragments and an interrupted-session journal support recovery of completed fragments. Use **Recover recordings** in the library menu. Unreadable files and damaged indexes are preserved; the unfinished tail of a take may be unavailable.

## Editing and presentation

Open a library clip to edit a saved timeline: split, remove, reorder, or add sections; enter exact in/out points; crop and change aspect; add zoom keyframes and audio fades; undo/redo. Edits save separately from the original video.

Draw arrows and freehand annotations, add timed text, and edit cursor spotlight and shortcut overlays. Shortcut capture is opt-in and needs Input Monitoring. It records modified shortcut combinations, omits plain typing, and stops reading keys while Secure Event Input is enabled. Cursor and shortcut data live in separate metadata files to keep the library index small.

Captions can be entered and edited manually, rendered into a video, or exported as SRT with timing remapped across cuts. Automatic transcription uses Apple's on-device recognizer only and requires Speech permission plus an available local language model. Unsupported languages/devices return an actionable error without sending audio to a cloud recognizer.

Exports include current-edit, widescreen, portrait, square, and small-file presets, plus saved custom presets. Edited copies show progress, support cancellation, and replace a destination only after success. Original library videos are protected as export destinations.

## Library and export queue

Search, favorite, rename, sort, import, reveal, share, and move clips to Trash. Projects and tags organize takes; multi-selection supports batch organization, favorites, Trash, and exports. Thumbnails decode away from the UI thread and use bounded caches.

The persistent export queue saves a snapshot of each edit and processes one job at a time. Pause, cancel, retry, and inspect completed copies in the Exports workspace. Interrupted jobs return to waiting after restart. Queued exports yield to recording and direct editor exports to limit competing media work.

Videos default to `~/Movies/Prism`. Library metadata, edit documents, presentation data, thumbnails, and the export queue live in `~/Library/Application Support/Prism`. No account is required.

## Shortcuts

Global shortcuts can be enabled in Preferences. Registration conflicts are reported; these hotkeys do not need Accessibility permission.

| Action | Global | With Prism focused |
| --- | --- | --- |
| Start / stop | Control Command R | Command Shift R |
| Pause / resume | Control Command P | Command Shift P |
| Add marker | Control Command M | Command Shift M |
| Library | — | Command L |
| Preferences | — | Command comma |
| Toggle sidebar | — | Command Option S |

## Performance

Capture uses a three-frame ScreenCaptureKit queue, hardware-accelerated encoding, serial media processing, bounded presenter pixel buffers, and throttled telemetry. Camera previews update at most twice per second. Annotation rasters cover their own bounds and use a 32 MB cache. Audio mixing copies compressed video packets to avoid a second video encode.

Static screens naturally deliver fewer frames. Processing measurements exclude asynchronous encoding. Actual performance depends on the Mac, source, devices, resolution, codec, disk, and other workloads. The release checks and their limits are documented in [verification](docs/VERIFICATION.md); they do not establish a universal zero-lag guarantee.

## Build and verify

Apple's command-line developer tools are sufficient. There are no third-party dependencies.

```sh
scripts/build.sh
scripts/verify.sh
scripts/verify.sh --benchmark
scripts/verify.sh --soak
scripts/verify.sh --live-benchmark
scripts/verify.sh --long-live-benchmark
```

The 26 functional/media checks exercise decoded video/audio, timeline exports, source preservation, cancellation, index rollback/recovery, MP4/MOV interrupted fragments, regions, saved areas, shortcut filtering, presentation rendering, edited subtitle timing, projects/tags, and queue persistence/priority.

`--benchmark` runs four paced six-second 1080p/4K 60 fps profiles with/without synthetic presenter frames. `--soak` runs a 60-second 4K60 profile with presenter composition and two synthetic PCM streams. JSON reports are saved under `build/`.

`--live-benchmark` records only the verifier's moving native window for ten seconds through ScreenCaptureKit. `--long-live-benchmark` runs the same capture for two minutes. They require screen access for the terminal host and an unlocked desktop; a locked desktop is explicitly reported as skipped. These tests do not grant permissions or change system privacy settings.

With Prism running, `scripts/verify.sh --capture-smoke` captures only Prism's window and checks pause/resume and playback. `scripts/ui-review.sh` creates an isolated GUI review host. Launch that host with `--render` to produce owned-view layout images and a main-actor interaction report without recording another application's content.

The [roadmap](docs/ROADMAP.md) records the independently committed development phases. Physical camera/microphone, speech permission/model availability, native picker interaction, device unplugging, and unlocked live UI/capture remain device-level release checks.
