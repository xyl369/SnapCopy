# SnapCopy

**Select-to-copy + region screenshot · runs locally · no network requests**

[Changelog](CHANGELOG.md) · [License](LICENSE)

## What is SnapCopy?

SnapCopy is a lightweight macOS menu bar utility that does exactly two things:

1. **Select to copy** — Highlight text and a small **Copy** button appears below your cursor. Click elsewhere to dismiss.
2. **Region screenshot** — Press **⌥Z**, drag to select an area, resize if needed, confirm — the image goes to your clipboard.

Built for one job: select-to-copy plus a region screenshot hotkey.

## Features

| Feature | Description |
|---------|-------------|
| Select to copy | Drag-select or double-click → **Copy** tip below cursor |
| Region capture | `⌥Z` with size badge and resize handles |
| Smart filtering | No false tips when selecting files in Finder or on web pages |
| Electron fallback | Brief ⌘C simulation when Accessibility API fails |
| Menu bar | Status, screenshot shortcut, quit |

## Install

**Option 1: Download Release (recommended)**

1. Go to [Releases](https://github.com/xyl369/SnapCopy/releases) and download the latest `.zip`
2. Extract `SnapCopy.app` to a fixed location (e.g. Applications)
3. Grant permissions below, then relaunch

> Currently ad-hoc signed. If macOS blocks it, right-click → Open, or build from source.

**Option 2: Build from source**

```bash
git clone https://github.com/xyl369/SnapCopy.git
cd SnapCopy
./Scripts/build_app.sh
open dist/SnapCopy.app
```

## Requirements

- macOS **14.0+**
- Apple Silicon (`arm64`) by default — edit `-target` in `Scripts/build_app.sh` for Intel
- Xcode Command Line Tools

## Permissions

1. Open **System Settings → Privacy & Security**
2. **Accessibility** — Add the `SnapCopy.app` you actually run (one fixed path only)
3. **Screen Recording** — Add the same `.app`
4. Remove stray black `exec` entries; keep only the `.app`
5. Quit and relaunch SnapCopy

When the menu bar shows **Ready · select to copy · ⌥Z screenshot**, you're set.

## Privacy & technical notes

**No network requests** in source — no HTTP, analytics, or auto-update. Screenshots and selections stay on your machine (clipboard only).

| Permission | Why |
|------------|-----|
| Accessibility | Read selected text; briefly simulate ⌘C in some apps |
| Screen Recording | Capture the region you select |

**⌘C fallback:** In Electron apps (Cursor, Chrome, etc.), when the Accessibility API cannot read the selection, SnapCopy briefly sends ⌘C, reads the clipboard, then restores the previous clipboard contents. This only happens on text selection — no background keylogging.

## Project structure

```
SnapCopy/
├── App/           # Entry, menu bar, permissions
├── Capture/       # Region screenshot UI + ScreenCaptureKit
├── Hotkey/        # ⌥Z global hotkey
├── Selection/     # Selection watcher, AX, clipboard fallback
├── UI/            # Copy tip overlay
└── Support/       # entitlements
Scripts/build_app.sh
```

~12 Swift files, no third-party dependencies.

## Known limitations

- Some apps don't expose selections via Accessibility API (⌘C fallback attempted)
- No copy tip when selecting files in Finder or on web pages
- Ad-hoc signed — redistribute with your own signing/notarization
- Tested mainly on Apple Silicon + macOS 14+

## Contributing

Issues and PRs welcome. Please keep the scope: **local, minimal, no network**.

## License

[MIT](LICENSE) © 2026 xyl369
