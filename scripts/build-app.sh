#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SwiftyStats"
BUNDLE_ID="com.swiftystats.app"
VERSION="1.0.0"
BUILD_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

INSTALL_FLAG=false
RUN_FLAG=false

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL_FLAG=true ;;
    --run) RUN_FLAG=true ;;
    *)
      echo "Usage: $0 [--install] [--run]" >&2
      exit 1
      ;;
  esac
done

echo "==> Building $APP_NAME (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

# Generate crisp macOS AppIcon.icns via CoreGraphics + iconutil
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" <<'SWIFT_ICON'
import AppKit
import Foundation

let iconsetPath = CommandLine.arguments[1]

func renderIcon(px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let inset = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colors = [
        NSColor(srgbRed: 0.09, green: 0.12, blue: 0.19, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.15, green: 0.20, blue: 0.32, alpha: 1.0).cgColor,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // Subtle top highlight
    let glowColors = [
        NSColor(srgbRed: 0.35, green: 0.65, blue: 1.0, alpha: 0.18).cgColor,
        NSColor(srgbRed: 0.35, green: 0.65, blue: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: rect.midX, y: rect.maxY * 0.88),
            startRadius: 0,
            endCenter: CGPoint(x: rect.midX, y: rect.maxY * 0.88),
            endRadius: rect.width * 0.65,
            options: []
        )
    }
    ctx.restoreGState()

    // Hairline border
    ctx.addPath(bgPath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.strokePath()

    // Three telemetry bars (CPU blue, RAM purple, Temp orange)
    let barSpecs: [(CGFloat, NSColor)] = [
        (0.42, NSColor(srgbRed: 0.32, green: 0.68, blue: 1.0, alpha: 1.0)),
        (0.68, NSColor(srgbRed: 0.68, green: 0.48, blue: 1.0, alpha: 1.0)),
        (0.54, NSColor(srgbRed: 1.0, green: 0.62, blue: 0.24, alpha: 1.0)),
    ]
    let barAreaW = rect.width * 0.62
    let barGap = rect.width * 0.08
    let barW = (barAreaW - barGap * 2) / 3.0
    let baseY = rect.minY + rect.height * 0.22
    let maxBarH = rect.height * 0.54
    let startX = rect.midX - barAreaW / 2.0

    for (i, spec) in barSpecs.enumerated() {
        let bx = startX + CGFloat(i) * (barW + barGap)
        let trackRect = CGRect(x: bx, y: baseY, width: barW, height: maxBarH)
        let trackPath = CGPath(roundedRect: trackRect, cornerWidth: barW * 0.35, cornerHeight: barW * 0.35, transform: nil)
        ctx.addPath(trackPath)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.09).cgColor)
        ctx.fillPath()

        let h = maxBarH * spec.0
        let fillRect = CGRect(x: bx, y: baseY, width: barW, height: h)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: barW * 0.35, cornerHeight: barW * 0.35, transform: nil)
        ctx.addPath(fillPath)
        ctx.setFillColor(spec.1.cgColor)
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, px) in entries {
    if let data = renderIcon(px: px) {
        let url = URL(fileURLWithPath: iconsetPath).appendingPathComponent(filename)
        try? data.write(to: url)
    }
}
SWIFT_ICON

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "==> Ad-hoc signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

APP_SIZE="$(du -sh "$APP_BUNDLE" | awk '{print $1}')"
echo "==> Done! Built $APP_BUNDLE ($APP_SIZE)"

TARGET_APP="$APP_BUNDLE"
if [[ "$INSTALL_FLAG" == "true" ]]; then
  echo "==> Installing to /Applications/$APP_NAME.app..."
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  TARGET_APP="/Applications/$APP_NAME.app"
  echo "==> Installed to $TARGET_APP"
fi

if [[ "$RUN_FLAG" == "true" ]]; then
  echo "==> Launching $TARGET_APP..."
  pkill -x "$APP_NAME" 2>/dev/null || true
  open "$TARGET_APP"
fi
