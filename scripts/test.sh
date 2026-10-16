#!/bin/sh
# Runs the JarvisKit tests. With only Command Line Tools installed (no Xcode),
# Swift Testing lives outside the default search paths, so point at it.
set -e
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
case "$DEV" in
  */CommandLineTools)
    F="$DEV/Library/Developer/Frameworks"
    L="$DEV/Library/Developer/usr/lib"
    exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" \
      -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@" ;;
  *)
    exec swift test "$@" ;;
esac
