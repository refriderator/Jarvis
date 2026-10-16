#!/bin/sh
# Builds Jarvis from this folder and installs it in Applications. Safe to run again to update.
# Double-click "Install Jarvis.command" to run it, or: scripts/install.sh
set -e
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$1"; exit 1; }

step "[1/4] Checking this Mac"
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
MINOR="$(sw_vers -productVersion | cut -d. -f2)"
# 15.6: the oldest macOS Apple's current build tools (Swift 6.2) install on.
if [ "$MAJOR" -lt 15 ] || { [ "$MAJOR" -eq 15 ] && [ "${MINOR:-0}" -lt 6 ]; }; then
  fail "Jarvis needs macOS 15.6 or newer (this Mac has $(sw_vers -productVersion)). Update in System Settings › General › Software Update."
fi
if [ "$MAJOR" -lt 26 ]; then
  echo "Note: on macOS $MAJOR, Apple's on-device AI isn't available (it needs macOS 26). Jarvis can download its"
  echo "own local model instead, or use Ollama or Claude: you'll pick during setup."
fi
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "Jarvis is built with Apple's free Command Line Tools, which aren't installed yet."
  echo "A window will ask to install them. When that's finished, run this installer again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi
SWIFT="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
case "$SWIFT" in
  6.[2-9]*|[7-9].*) echo "macOS $(sw_vers -productVersion), Swift $SWIFT: good." ;;
  *) fail "Jarvis needs Swift 6.2 or newer (found ${SWIFT:-none}). Update the Command Line Tools in System Settings › General › Software Update." ;;
esac

step "[2/4] Making a signing certificate (first time only)"
echo "This keeps Jarvis's permissions (microphone, calendar...) when you update it later."
scripts/make-signing-cert.sh
echo "If a window asks to let codesign use the key, enter your Mac password and choose Always Allow."

step "[3/4] Building Jarvis (a few minutes the first time)"
scripts/bundle.sh release

step "[4/4] Installing in Applications"
osascript -e 'tell application id "io.github.jarvis-public" to quit' >/dev/null 2>&1 || true
sleep 1
# Update the copy already installed wherever it was moved to (a folder inside Applications), so there's only ever one.
TARGET="$(find /Applications -maxdepth 2 -name Jarvis.app -type d 2>/dev/null | head -1)"
TARGET="${TARGET:-/Applications/Jarvis.app}"
rm -rf "$TARGET"
ditto build/Jarvis.app "$TARGET"
open "$TARGET"

printf '\n\033[32mJarvis is installed and running.\033[0m\n'
echo "Look for it in the notch at the top of the screen. The first time, it walks you through setup."
