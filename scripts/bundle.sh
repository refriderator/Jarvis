#!/bin/sh
# Builds build/Jarvis.app from the Swift package (no Xcode project needed).
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Jarvis
APP=build/Jarvis.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c "$CONFIG" --show-bin-path)/Jarvis" "$APP/Contents/MacOS/Jarvis"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Where this copy was built from, so Settings › General › Update can pull and rebuild it.
/usr/libexec/PlistBuddy -c "Add :JarvisSourceFolder string $(pwd)" "$APP/Contents/Info.plist"
# The release it was built from (the latest tag, "v1.3" → 1.3) and the GitHub repository it came from, so Jarvis
# can tell when a newer release is out. Untagged (before the first release) it stays Info.plist's 0.1.0.
TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$TAG" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${TAG#v}" "$APP/Contents/Info.plist"
fi
REPOSITORY="$(git remote get-url origin 2>/dev/null | sed -n 's#^.*github\.com[:/]\(.*\)$#\1#p' | sed 's#\.git$##')"
if [ -n "$REPOSITORY" ]; then
  /usr/libexec/PlistBuddy -c "Add :JarvisRepository string $REPOSITORY" "$APP/Contents/Info.plist"
fi
# The icon (redraw it with scripts/make-icon.sh).
mkdir -p "$APP/Contents/Resources"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Settings › General › Uninstall runs it from here, so it works without the source folder.
cp scripts/uninstall.sh "$APP/Contents/Resources/uninstall.sh"
# llama.cpp ships as a prebuilt framework; it must sit inside the app for the built-in model.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$(find .build/artifacts -type d -path '*macos-arm64_x86_64/llama.framework' | head -1)" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Jarvis"
# Sign with the local certificate if scripts/make-signing-cert.sh made one
# (stable identity, permissions survive rebuilds), else ad-hoc.
IDENTITY="${JARVIS_SIGN_IDENTITY:-Jarvis Local Signing}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/llama.framework"
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/Frameworks/llama.framework"
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
