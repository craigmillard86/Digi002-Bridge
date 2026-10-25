#!/bin/bash
# Builds "002 Bridge.app" from the BridgeApp target into build/, signed ad hoc so it runs.
# With --install, copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product BridgeApp
app="build/002 Bridge.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/BridgeApp "$app/Contents/MacOS/002 Bridge"
swift tools/make-icon.swift build/AppIcon.icns
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp docs/user-guide.md docs/install.md docs/config.md "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>002 Bridge</string>
    <key>CFBundleIdentifier</key>
    <string>com.digi002.bridge</string>
    <key>CFBundleName</key>
    <string>002 Bridge</string>
    <key>CFBundleDisplayName</key>
    <string>002 Bridge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Bridges a Digi 002 control surface to Logic Pro as a Mackie Control.</string>
</dict>
</plist>
EOF
echo -n "APPL????" > "$app/Contents/PkgInfo"
codesign --force --deep --sign - "$app"
echo "built $app"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/002 Bridge.app"
    cp -R "$app" /Applications/
    echo "installed /Applications/002 Bridge.app"
fi
