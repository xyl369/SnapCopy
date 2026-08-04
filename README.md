# SnapCopy

**Select-to-copy + region screenshot · fully local · zero network**

**划词复制 + 区域截屏 · 纯本地 · 零网络请求**

No analytics · no auto-update · no cloud · no China-vendor SDKs  
无埋点 · 无自动更新 · 无云 · 无国产厂商 SDK

[English](#english) · [中文](#中文) · [Threat model](#threat-model--威胁模型) · [Changelog](CHANGELOG.md) · [License](LICENSE)

---

## Threat model / 威胁模型

| Goal | Status |
|------|--------|
| Avoid **China-company** monitoring / SDKs / account upload | **Yes** — no network stack in app code |
| Keep selections & screenshots **on this Mac only** | **Yes** — clipboard only |
| Pure local / offline usable | **Yes** — no HTTP, no phone-home |
| Auditable source | **Yes** — ~13 Swift files, no third-party deps |

**What leaves the machine**

| Data | Destination |
|------|-------------|
| Selected text / screenshot pixels | **Nowhere** — only system clipboard |
| Telemetry / crash reports / update checks | **None** in source |

**Permissions (local only)**

| Permission | Why |
|------------|-----|
| Accessibility | Read selection; brief ⌘C fallback in some Electron apps |
| Screen Recording | Capture the region you choose |

**What this is *not***

- Not a PopClip clone with plugins / AI / cloud translate
- Not a Chinese vendor “划词” client
- Not notarized by Apple by default (ad-hoc signed Release — prefer build from source if you require a trust chain)

---

## English

### What is SnapCopy?

A lightweight macOS menu bar utility that does exactly two things:

1. **Select to copy** — Highlight text → **Copy** tip below the cursor; click elsewhere to dismiss.
2. **Region screenshot** — Press **⌥Z**. The desktop freezes first (including Dock menus/popovers); hover a fully visible window (or outside windows for full screen), click to lock, adjust if needed, then Confirm — the image is cropped from that freeze onto your clipboard. Drag still works for a custom region.

Built for one job: select-to-copy plus a region screenshot hotkey — **without** network, AI, or vendor telemetry.

### Features

| Feature | Description |
|---------|-------------|
| Select to copy | Drag-select or double-click → **Copy** tip |
| Region capture | `⌥Z` — freeze backdrop, window / full-screen hover, drag, resize, Confirm |
| Smart filtering | No false tips when selecting files in Finder or on web pages |
| Electron fallback | Brief ⌘C simulation when Accessibility API fails |
| Menu bar | Status, screenshot shortcut, quit |

### Install

**Option 1: Download Release**

1. [Releases](https://github.com/xyl369/SnapCopy/releases) → latest `.zip`
2. Put `SnapCopy.app` in a fixed path (e.g. Applications)
3. Grant permissions below, then relaunch

> Ad-hoc signed. If macOS blocks it: right-click → Open, or **build from source** (recommended for trust).

**Option 2: Build from source (preferred for audit)**

```bash
git clone https://github.com/xyl369/SnapCopy.git
cd SnapCopy
./Scripts/build_app.sh
open dist/SnapCopy.app
```

### Requirements

- macOS **14.0+**
- Apple Silicon (`arm64`) by default — edit `-target` in `Scripts/build_app.sh` for Intel
- Xcode Command Line Tools

### Permissions

1. **System Settings → Privacy & Security**
2. **Accessibility** — add the `SnapCopy.app` you actually run (one fixed path)
3. **Screen Recording** — same `.app`
4. Remove stray black `exec` entries; keep only the `.app`
5. Quit and relaunch

Menu bar: **Ready · select to copy · ⌥Z screenshot** means OK.

### Privacy & technical notes

Source contains **no network requests** — no `URLSession`, analytics, or auto-update. Selections and screenshots stay on-device (clipboard only).

**⌘C fallback:** In Electron apps (e.g. Chrome, some editors), when Accessibility cannot read the selection, SnapCopy briefly sends ⌘C, reads the clipboard, then restores prior clipboard contents. Only on text selection — not background keylogging.

### Project structure

```
SnapCopy/
├── App/           # Entry, menu bar, permissions
├── Capture/       # Region screenshot + ScreenCaptureKit
├── Hotkey/        # ⌥Z
├── Selection/     # Watcher, AX, clipboard fallback
├── UI/            # Copy tip
└── Support/       # entitlements
Scripts/build_app.sh
```

### Known limitations

- Some apps do not expose selection via AX (⌘C fallback attempted)
- No copy tip when selecting files in Finder or file names on web pages
- Ad-hoc signed — redistribute with your own signing/notarization
- Tested mainly on Apple Silicon + macOS 14+

### Contributing

Keep the boundary: **local, minimal, zero network, no vendor SDKs**.

---

## 中文

### 这是什么

轻量 macOS 菜单栏工具，只做两件事：

1. **划词复制** — 选中文字后弹出 **Copy**  
2. **区域截屏** — **⌥Z** 冻结整屏后框选，图进剪贴板  

适合要「选中即复制 + 快捷键截屏」，且要求**无网络、无埋点、无国产划词客户端**的场景。

### 功能

| 功能 | 说明 |
|------|------|
| 划词复制 | 拖选 / 双击 → **Copy** |
| 区域截屏 | `⌥Z` 冻结、窗口/整屏预选、拖拽、Confirm |
| 智能过滤 | Finder / 网页选文件名时不误弹 |
| Electron 兼容 | AX 读不到时短暂模拟 ⌘C |
| 菜单栏 | 状态、快捷键、退出 |

### 安装

**方式一：Release** — [Releases](https://github.com/xyl369/SnapCopy/releases)  
**方式二：源码编译（更利于审计）**

```bash
git clone https://github.com/xyl369/SnapCopy.git
cd SnapCopy
./Scripts/build_app.sh
open dist/SnapCopy.app
```

### 权限

辅助功能 + 屏幕录制，添加你实际运行的那个 `SnapCopy.app`。

### 隐私

源码**无网络请求**；选区与截屏只进本机剪贴板。无埋点、无自动更新、无云同步。

### 参与贡献

保持「本地、极简、零网络、无厂商 SDK」。

---

## License

[MIT](LICENSE) © 2026 xyl369
