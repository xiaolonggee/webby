#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build-webby/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-webby/module-cache"
swift build -c release --scratch-path .build-webby --disable-sandbox
APP="${WEBBY_APP_OUTPUT:-$PWD/dist/Webby.app}"
mkdir -p "$APP/Contents/MacOS"
cp .build-webby/release/Webby "$APP/Contents/MacOS/Webby"
mkdir -p "$APP/Contents/Resources/Webby_Webby.bundle"
cp -R .build-webby/release/Webby_Webby.bundle/. "$APP/Contents/Resources/Webby_Webby.bundle/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Webby</string>
<key>CFBundleIdentifier</key><string>app.webby.desktop</string>
<key>CFBundleName</key><string>Webby</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
