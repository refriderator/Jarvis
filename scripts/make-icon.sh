#!/bin/sh
# Redraws Support/AppIcon.icns from scripts/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swift scripts/make-icon.swift "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$TMP/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Support/AppIcon.icns
cp "$TMP/icon.png" Support/AppIcon.png
rm -rf "$TMP"
echo "Wrote Support/AppIcon.icns"
