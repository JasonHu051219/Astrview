#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
app="$root/build/Astrview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$root/build/module-cache"
xcrun --sdk macosx swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$root/build/module-cache" -framework AppKit -framework WebKit \
    "$root"/Sources/*.swift -o "$app/Contents/MacOS/Astrview"
/usr/bin/plutil -lint "$root/Info.plist"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/LICENSE" "$app/Contents/Resources/LICENSE.txt"

# Ship the optimized multi-resolution icon without requiring a PNG optimizer at build time.
cp "$root/Assets/Astrview.icns" "$app/Contents/Resources/Astrview.icns"
/usr/bin/sips -s format png -z 80 96 "$root/Assets/AstrviewMenuBar.svg" \
    --out "$app/Contents/Resources/AstrviewMenuBar.png" >/dev/null
/usr/bin/codesign --force --sign - "$app"
# Mark the bundle itself as updated, not just the files inside it.
/usr/bin/touch "$app"
printf 'Built %s\n' "$app"
