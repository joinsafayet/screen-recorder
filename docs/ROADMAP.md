# Prism 3 development phases

Each phase is committed independently. Source originals and local recording data remain preserved.

1. [x] Studio layout: resizable sidebar, larger preview, collapsible inspector, compact controls.
2. [x] Selection: native source picker; adjustable, constrained, saved recording regions.
3. [x] Preparation: actual camera/audio preview, test takes, storage/output estimates.
4. [x] Recovery: interrupted-session journal, recoverable movie fragments, background disk checks.
5. [x] Timeline: multiple cuts, crop/aspect, zoom keyframes, audio fades, undo/redo, saved edits.
6. [x] Presentation: editable drawings/arrows, keystroke capture, spotlight, local caption workflow.
7. [x] Library/export: projects, tags, batch actions, persistent export queue, output presets.
8. [x] Validation and release: sustained encoder/interruption checks, owned-view UI stress, theme/compact layout polish, package checks. Unlocked desktop and physical device checks remain documented below.

Permission-dependent features are opt-in. Media tests use temporary folders and own verifier windows. Physical device tests need real devices and permissions; signing/notarization needs release credentials.

Phase 2 validation: 17 functional/media checks passed, including region handles, screen-edge bounds, aspect constraints, and saved area persistence.
Phase 3 validation: 18 media and functional checks passed. Device meters use actual buffers; preview images are limited to 2 fps. Physical device permission checks remain manual.
Phase 4 validation: 20 checks passed. An abrupt-exit fixture produced an unfinalized movie whose completed fragment decoded and recovered into the library with its title and valid markers.
Phase 5 validation: 22 checks passed, including actual multi-cut square exports, unchanged source bytes, cancellation preserving a destination, saved edits, and undo/redo. The preview factory uses the asynchronous AVFoundation API.
Phase 6 validation: 24 checks passed, including rendered arrows, pointer interpolation, shortcut filtering, subtitle remapping and source preservation. Automatic captions require an available on-device language model and user permission; manual captions and SRT export work independently.
Phase 7 validation: 26 checks passed. Project/tag organization and favorites persist, protected library files cannot be export destinations, queued edits survive reload, and capture prevents queue execution.

Phase 8 validation (2026-10-12): all 26 functional/media checks passed, now including interrupted MP4 and MOV recovery, decoded timeline audio fades, and presentation sidecar persistence. The 60-second paced 4K60 presenter/dual-audio soak saved 3,600 frames with zero video/audio drops, averaging 4.49 ms frame processing and 128 MB peak resident memory. Owned-view renders at 1240 × 860 and 940 × 680 exposed and verified fixes for compact controls. A 120-action main-actor/layout stress run completed; it does not measure visible animation frame rate. Prism 3.0.0 was built as an arm64 app and ZIP, with valid local code signing and bundle metadata. See [verification](VERIFICATION.md) for evidence and remaining device-level checks.

The desktop was locked during final verification. The two-minute moving-window ScreenCaptureKit benchmark explicitly skipped; unlocked GUI interaction, physical devices/unplugging, Input Monitoring, and Speech permission/model availability remain manual checks. They are not reported as passed.
