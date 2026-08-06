#!/bin/sh
# Builds Jotter.app (no Xcode project needed) and installs it to /Applications.
#   ./build-app.sh                build + install + launch
#   ./build-app.sh --no-install   just build into ./build/Jotter.app
#   ./build-app.sh --release      build + zip to ./build/Jotter-<version>.zip
set -e
cd "$(dirname "$0")"

VERSION=1.3
APP=build/Jotter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -parse-as-library -O Jotter.swift -o "$APP/Contents/MacOS/Jotter"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>                <string>Jotter</string>
	<key>CFBundleDisplayName</key>         <string>Jotter</string>
	<key>CFBundleIdentifier</key>          <string>com.ryanchankh.Jotter</string>
	<key>CFBundleExecutable</key>          <string>Jotter</string>
	<key>CFBundlePackageType</key>         <string>APPL</string>
	<key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
	<key>CFBundleVersion</key>             <string>1</string>
	<key>CFBundleIconFile</key>            <string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>      <string>13.0</string>
	<key>LSUIElement</key>                 <true/>
	<key>LSApplicationCategoryType</key>   <string>public.app-category.utilities</string>
	<key>NSPrincipalClass</key>            <string>NSApplication</string>
	<key>NSHighResolutionCapable</key>     <true/>
	<key>NSHumanReadableCopyright</key>    <string>© 2026 Ryan Chan Kwan Ho. All rights reserved.</string>
</dict>
</plist>
PLIST

echo "Rendering icon…"
cat > build/makeicon.swift <<'SWIFT'
import AppKit
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(srgbRed: 0.29, green: 0.56, blue: 0.98, alpha: 1),
           ending: NSColor(srgbRed: 0.11, green: 0.32, blue: 0.87, alpha: 1))!
    .draw(in: path, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { r in
        symbol.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
    }
    let s = tinted.size
    let scale = min(440 / max(s.width, s.height), 10)
    let w = s.width * scale, h = s.height * scale
    tinted.draw(in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift build/makeicon.swift build/icon_1024.png
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

case "$1" in
--release)
  ditto -c -k --keepParent "$APP" "build/Jotter-${VERSION}.zip"
  echo "Release zip: build/Jotter-${VERSION}.zip"
  ;;
--no-install)
  ;;
*)
  pkill -x Jotter 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Jotter.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Jotter.app — launching"
  open /Applications/Jotter.app
  ;;
esac
