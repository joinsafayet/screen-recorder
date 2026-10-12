# Prism 3 development phases

Each phase is committed independently. Source originals and local recording data remain preserved.

1. [x] Studio layout: resizable sidebar, larger preview, collapsible inspector, compact controls.
2. [x] Selection: native source picker; adjustable, constrained, saved recording regions.
3. Preparation: actual camera/audio preview, test takes, storage/output estimates.
4. Recovery: interrupted-session journal, recoverable movie fragments, background disk checks.
5. Timeline: multiple cuts, crop/aspect, zoom keyframes, audio fades, undo/redo, saved edits.
6. Presentation: editable drawings/arrows, keystroke capture, spotlight, local caption workflow.
7. Library/export: projects, tags, batch actions, persistent export queue, output presets.
8. Validation: long capture and interruption tests, UI stress, theme/focus polish, package checks.

Permission-dependent features are opt-in. Media tests use temporary folders and own verifier windows. Physical device tests need real devices and permissions; signing/notarization needs release credentials.

Phase 2 validation: 17 functional/media checks passed, including region handles, screen-edge bounds, aspect constraints, and saved area persistence.
