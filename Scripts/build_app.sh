#!/usr/bin/env bash
# Build SnapCopy.app with Command Line Tools (no full Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/SnapCopy"
DIST="$ROOT/dist"
APP="$DIST/SnapCopy.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

echo "==> Cleaning $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Resolved Info.plist (no Xcode build vars)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>SnapCopy</string>
	<key>CFBundleExecutable</key>
	<string>SnapCopy</string>
	<key>CFBundleIdentifier</key>
	<string>app.snapcopy.macos</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>SnapCopy</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.5</string>
	<key>CFBundleVersion</key>
	<string>6</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSAccessibilityUsageDescription</key>
	<string>SnapCopy needs Accessibility permission to read selected text and show the copy tip.</string>
	<key>NSScreenCaptureUsageDescription</key>
	<string>SnapCopy needs Screen Recording permission to capture the screen region you select.</string>
</dict>
</plist>
PLIST

cp "$SRC/Support/SnapCopy.entitlements" "$RES_DIR/" 2>/dev/null || true

# macOS ships Bash 3.2 — avoid mapfile
SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done <<EOF
$(find "$SRC" -name '*.swift' | sort)
EOF

echo "==> Compiling ${#SOURCES[@]} Swift files"
echo "    SDK: $SDK"
echo "    Target: $TARGET"

# SwiftUI + AppKit menu bar app
xcrun swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -O \
  "${SOURCES[@]}" \
  -o "$MACOS_DIR/SnapCopy" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework Foundation \
  -framework Combine \
  -framework ScreenCaptureKit \
  -framework Carbon

echo "==> Ad-hoc codesign"
xattr -cr "$APP" 2>/dev/null || true
xattr -cr "$MACOS_DIR/SnapCopy" 2>/dev/null || true
find "$APP" -name '._*' -delete 2>/dev/null || true
find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
# Clear Finder info that breaks codesign
dot_clean -m "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" || {
  # Retry after stripping extended attributes again
  xattr -c "$MACOS_DIR/SnapCopy" 2>/dev/null || true
  codesign --force --sign - "$MACOS_DIR/SnapCopy"
  codesign --force --deep --sign - "$APP"
}

echo "==> Done: $APP"
echo "    Launch: open \"$APP\""
echo "    Then grant Accessibility + Screen Recording in System Settings."
