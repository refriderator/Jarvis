#!/bin/sh
# Removes Jarvis from this Mac: the app, its settings, downloaded models, logs, saved keys and its permissions.
# Settings › General › Uninstall Jarvis… runs it, or: sh ~/Jarvis/scripts/uninstall.sh
# Leaves alone: Claude Code, Codex and Ollama (separate tools), and website passwords saved from the Web tab
# (they're in your login keychain with your other passwords).
# Usage: uninstall.sh [folder Jarvis was downloaded to]
ID="io.github.jarvis-public"
NAME="Jarvis.app"
SUPPORT="$HOME/Library/Application Support/Jarvis"
SOURCE="${1:-}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# Only apps that really are Jarvis (by bundle id), wherever in Applications they were moved.
APPS="$(find /Applications -maxdepth 2 -name "$NAME" -type d 2>/dev/null | while read -r app; do
  [ "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$ID" ] && echo "$app"
done)"
DATA=""
for path in "$SUPPORT" "$HOME/Library/Caches/$ID" "$HOME/Library/WebKit/$ID" "$HOME/Library/HTTPStorages/$ID" \
            "$HOME/Library/Saved Application State/$ID.savedState"; do
  [ -e "$path" ] && DATA="$DATA$path
"
done

bold "This removes Jarvis from this Mac:"
printf '%s\n' "$APPS" "$DATA" | while read -r path; do
  [ -n "$path" ] && printf '  %6s  %s\n' "$(du -sh "$path" 2>/dev/null | cut -f1)" "$path"
done
echo "  and Jarvis's saved keys, its signing certificate, and its permissions (microphone, calendar...)."
echo "  Settings, downloaded models and conversation logs can't be got back."
echo
printf 'Type yes to remove it all: '
read -r answer
[ "$answer" = "yes" ] || { echo "Nothing was removed."; exit 0; }

osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
sleep 1
printf '%s\n' "$APPS" "$DATA" | while read -r path; do [ -n "$path" ] && rm -rf "$path"; done
defaults delete "$ID" >/dev/null 2>&1 || true
# Every key Jarvis saved (Claude, Notion...) is under its own service name.
while security delete-generic-password -s "$ID" >/dev/null 2>&1; do :; done
security delete-identity -c "Jarvis Local Signing" >/dev/null 2>&1 || true
tccutil reset All "$ID" >/dev/null 2>&1 || true

if [ -n "$SOURCE" ] && [ -d "$SOURCE/.git" ]; then
  echo
  printf 'Also delete the downloaded copy in %s? (y/N): ' "$SOURCE"
  read -r answer
  case "$answer" in y|Y|yes) rm -rf "$SOURCE" && echo "Deleted it." ;; *) echo "Kept it." ;; esac
fi

printf '\n\033[32mJarvis is removed.\033[0m You can close this window.\n'
