#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
app="$root/build/Astrview.app"
mkdir -p "$app/Contents/MacOS" "$root/build/module-cache"
xcrun --sdk macosx swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$root/build/module-cache" -framework AppKit -framework WebKit \
    "$root"/Sources/*.swift -o "$app/Contents/MacOS/Astrview"
/usr/bin/plutil -lint "$root/Info.plist"
cp "$root/Info.plist" "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
