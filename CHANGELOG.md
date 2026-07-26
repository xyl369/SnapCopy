# Changelog

## [0.1.5] — 2026-07-26

### Fixed

- Screenshot Confirm now crops from the freeze taken at ⌥Z press, instead of live-recapturing after overlays dismiss Dock menus / popovers
- Freeze all displays before showing overlays or activating the app, so transient Dock UI is included in the buffer

## [0.1.4] — 2026-07-26

### Added

- Screenshot: freeze the desktop at the moment ⌥Z is pressed (stable backdrop while selecting)
- Screenshot: hover a fully visible window to preview it; click to lock, then Confirm to capture
- Screenshot: hover outside windows (desktop gap, menu bar, Dock, screen edge) to preview the full screen

### Fixed

- Selection preview no longer mirrors when painting the frozen backdrop
- Occluded windows are not offered for auto-frame (only fully visible windows)
- Dock / menu bar strips are not treated as app windows
- Copy tip uses a fixed light style and no longer follows system appearance

## [0.1.3] — 2026-07-24

### Fixed

- Clipboard ⌘C fallback: require pasteboard `changeCount` to change; do not resurface stale clipboard text when dragging a page/window with no selection
- Vertical (top-to-bottom) multi-line selection: allow a higher drag-distance cap for vertical-dominant gestures

### Improved

- Copy tip: click anywhere on the tip surface to copy (including click-through via global monitor)

## [0.1.2] — 2026-07-24

### Improved

- Screenshot Confirm / Cancel buttons: solid high-contrast colors on the dim overlay
- Select-to-copy on Notion-style / table web pages: allow AX Group/Cell hosts; restore smart ⌘C fallback when AX cannot read the selection
- Fewer false tips when dragging a browser window: ignore unchanged selection on large moves; limit clipboard fallback to selection-like drag distances

## [0.1.1] — 2026-07-24

### Fixed

- No false “Copy” tip when selecting filenames/attachments on web or cloud-drive pages
- No select-to-copy while managing files in Finder
- AX selection: role and selected-range length checks to reduce non-text false triggers
- Clipboard fallback: detect file URLs so “selected file” is not treated as text selection

### Docs

- English README: install guide, ⌘C fallback notes, privacy wording
- Release notes: permissions and ad-hoc signing

## [0.1.0] — 2026-07-24

### Added

- Select to copy: **Copy** tip below cursor
- Region screenshot: ⌥Z selection to clipboard
- Menu bar status and hotkey
- Electron clipboard fallback (⌘C)
- MIT open-source release
