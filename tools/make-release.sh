#!/bin/bash
# Builds "002 Bridge.app" and zips it with the install notes and the button guide, ready
# to send to someone. Output: build/002-Bridge-<version>.zip
#
# Signing: the app is signed ad hoc, so recipients get Gatekeeper's "cannot be verified"
# warning and open it via right-click > Open (macOS 11-14) or Privacy & Security > Open
# Anyway (macOS 15). With an Apple Developer ID, set SIGN_IDENTITY to the "Developer ID
# Application: ..." certificate and the app is signed with it instead; notarise the zip
# afterwards with `xcrun notarytool submit <zip> --keychain-profile <profile> --wait` and
# `xcrun stapler staple "build/002 Bridge.app"` to remove the warning entirely.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep -A1 CFBundleShortVersionString tools/make-app.sh | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
tools/make-app.sh
app="build/002 Bridge.app"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$app"
    echo "signed with $SIGN_IDENTITY"
fi

stage="build/release-stage"
rm -rf "$stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
cp docs/install.md "$stage/Read me first.md"
cp docs/user-guide.md "$stage/Button guide.md"
zip="build/002-Bridge-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc "$stage" "$zip"
rm -rf "$stage"
echo "release: $zip"
