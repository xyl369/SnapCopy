# SnapCopy

**Select-to-copy + region screenshot · runs locally · no network requests**

**划词复制 + 区域截屏 · 本地运行 · 无网络请求**

[English](#english) · [中文](#中文) · [Changelog](CHANGELOG.md) · [License](LICENSE)

---

## English

### What is SnapCopy?

SnapCopy is a lightweight macOS menu bar utility that does exactly two things:

1. **Select to copy** — Highlight text and a small **Copy** button appears below your cursor. Click elsewhere to dismiss.
2. **Region screenshot** — Press **⌥Z**, drag to select an area, resize if needed, confirm — the image goes to your clipboard.

Built for one job: select-to-copy plus a region screenshot hotkey.

### Features

| Feature | Description |
|---------|-------------|
| Select to copy | Drag-select or double-click → **Copy** tip below cursor |
| Region capture | `⌥Z` with size badge and resize handles |
| Smart filtering | No false tips when selecting files in Finder or on web pages |
| Electron fallback | Brief ⌘C simulation when Accessibility API fails |
| Menu bar | Status, screenshot shortcut, quit |

### Install

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

### Requirements

- macOS **14.0+**
- Apple Silicon (`arm64`) by default — edit `-target` in `Scripts/build_app.sh` for Intel
- Xcode Command Line Tools

### Permissions

1. Open **System Settings → Privacy & Security**
2. **Accessibility** — Add the `SnapCopy.app` you actually run (one fixed path only)
3. **Screen Recording** — Add the same `.app`
4. Remove stray black `exec` entries; keep only the `.app`
5. Quit and relaunch SnapCopy

When the menu bar shows **Ready · select to copy · ⌥Z screenshot**, you're set.

### Privacy & technical notes

**No network requests** in source — no HTTP, analytics, or auto-update. Screenshots and selections stay on your machine (clipboard only).

| Permission | Why |
|------------|-----|
| Accessibility | Read selected text; briefly simulate ⌘C in some apps |
| Screen Recording | Capture the region you select |

**⌘C fallback:** In Electron apps (Cursor, Chrome, etc.), when the Accessibility API cannot read the selection, SnapCopy briefly sends ⌘C, reads the clipboard, then restores the previous clipboard contents. This only happens on text selection — no background keylogging.

### Project structure

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

### Known limitations

- Some apps don't expose selections via Accessibility API (⌘C fallback attempted)
- No copy tip when selecting files in Finder or on web pages
- Ad-hoc signed — redistribute with your own signing/notarization
- Tested mainly on Apple Silicon + macOS 14+

### Contributing

Issues and PRs welcome. Please keep the scope: **local, minimal, no network**.

---

## 中文

### 这是什么

SnapCopy 是一个轻量的 macOS 菜单栏工具，只做两件事：

1. **划词复制** — 选中文字后，在鼠标下方弹出 **Copy**；点别处消失
2. **区域截屏** — 按 **⌥Z** 拖拽框选，可调大小，确认后图片进入剪贴板

适合只要「选中即复制 + 快捷键截屏」的场景。

### 功能

| 功能 | 说明 |
|------|------|
| 划词复制 | 拖选或双击选词 → 鼠标下方弹出 **Copy** |
| 区域截屏 | `⌥Z` 框选，带尺寸提示与拖拽手柄 |
| 智能过滤 | Finder 操作文件、网页选附件/文件名时不误弹提示 |
| Electron 兼容 | Accessibility 读不到选区时，短暂模拟 ⌘C |
| 菜单栏 | 状态、截屏快捷键、退出 |

### 安装

**方式一：下载 Release（推荐）**

1. 打开 [Releases](https://github.com/xyl369/SnapCopy/releases) 下载最新 `.zip`
2. 解压后将 `SnapCopy.app` 放到固定路径（建议「应用程序」）
3. 按下方权限设置授权后重新打开

> 当前为 ad-hoc 签名。若 macOS 拦截，请右键 → 打开，或从源码编译。

**方式二：从源码编译**

```bash
git clone https://github.com/xyl369/SnapCopy.git
cd SnapCopy
./Scripts/build_app.sh
open dist/SnapCopy.app
```

### 系统要求

- macOS **14.0+**
- 默认 Apple Silicon（`arm64`）；Intel 请修改 `Scripts/build_app.sh` 中的 `-target`
- Xcode Command Line Tools

### 权限设置

1. 打开 **系统设置 → 隐私与安全性**
2. **辅助功能** — 添加你实际运行的 `SnapCopy.app`（固定一个路径）
3. **屏幕录制** — 添加同一个 `.app`
4. 删除列表中黑色的 `exec` 条目，只保留 `.app`
5. 退出并重新打开 SnapCopy

菜单栏显示 **Ready · select to copy · ⌥Z screenshot** 即表示正常。

### 隐私与技术说明

源码中**无网络请求** — 无 HTTP、无埋点、无自动更新。截屏与选区内容只写入本机剪贴板。

| 权限 | 用途 |
|------|------|
| 辅助功能 | 读取选中文字；在部分 App 中短暂模拟 ⌘C |
| 屏幕录制 | 截取你框选的屏幕区域 |

**⌘C 回退：** 在 Cursor、Chrome 等 Electron 应用中，Accessibility API 有时读不到选区。SnapCopy 会短暂发送一次 ⌘C、读取剪贴板，然后尽量恢复原剪贴板内容。仅在划词触发时发生，不会后台监听键盘。

### 项目结构

约 12 个 Swift 文件，无第三方依赖。目录结构见上方 English 章节。

### 已知限制

- 部分 App 无法通过 Accessibility API 读取选区（会尝试 ⌘C 回退）
- Finder 内操作文件、网页选中文件名时不显示复制提示
- ad-hoc 签名，分发给他人需自行签名或公证
- 主要在 Apple Silicon + macOS 14+ 上测试

### 参与贡献

欢迎 Issue 与 PR。请保持「本地、极简、无网络」的产品边界。

---

## License

[MIT](LICENSE) © 2026 xyl369
