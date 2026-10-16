#!/bin/sh
# Rebuilds and relaunches Jarvis.
set -e
cd "$(dirname "$0")/.."
# Only the app: fine-tuning scripts can be running the same binary (.build/debug/Jarvis --local-prompt) at the same time.
pkill -f "build/Jarvis.app/Contents/MacOS/Jarvis" || true
scripts/bundle.sh "${1:-debug}"
open build/Jarvis.app
