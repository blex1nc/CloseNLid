#!/bin/bash
# SwiftPM çıktısını çalıştırılabilir bir .app paketine dönüştürür.
# Xcode gerekmez; yalnızca Command Line Tools yeterlidir.
set -euo pipefail

APP_NAME="CloseNLid"
EXECUTABLE="CloseNLid"
BUNDLE_ID="com.toprak.closenlid"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Building release binary"
# Universal (arm64 + x86_64) derleme SwiftPM'de xcbuild gerektirir ve xcbuild
# yalnızca tam Xcode kurulumuyla gelir — Command Line Tools yetmez. Xcode varsa
# universal, yoksa bu makinenin mimarisi kullanılır.
if swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT" 2>/dev/null; then
    BIN="$ROOT/.build/apple/Products/Release/$EXECUTABLE"
    echo "    universal (arm64 + x86_64)"
else
    swift build -c release --package-path "$ROOT"
    BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$EXECUTABLE"
    echo "    native only ($(uname -m)) — install Xcode for a universal build"
fi

if [ ! -f "$BIN" ]; then
    echo "ERROR: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app"
mkdir -p "$DIST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>        <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <!-- Dock simgesi yok: bu bir durum çubuğu uygulaması. -->
    <key>LSUIElement</key>                   <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Rendering icon"
"$APP/Contents/MacOS/$EXECUTABLE" --make-icon "$WORK/icon.png" > /dev/null
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
# Ad-hoc imza Apple Developer üyeliği gerektirmez ve bu Mac'te çalışmaya yeter.
# SMAppService (girişte başlat) imzasız bir paketi kabul etmiyor.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""
