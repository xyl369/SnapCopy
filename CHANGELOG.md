# Changelog

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
