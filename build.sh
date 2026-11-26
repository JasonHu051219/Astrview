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

# Render the vector master once, then create all Finder/Dock icon representations.
icon_work="$(mktemp -d "$root/build/.astrview-icon.XXXXXXXX")"
# Verify the resolved path before removing the temporary icon workspace.
icon_work="$(cd -- "$icon_work" && pwd -P)"
case "$icon_work" in
    "$root/build/".astrview-icon.????????) ;;
    *) printf 'Unexpected temporary icon path: %s\n' "$icon_work" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$icon_work"' EXIT
iconset="$icon_work/Astrview.iconset"
master="$icon_work/Astrview.png"
mkdir -p "$iconset"
/usr/bin/sips -s format png "$root/Assets/Astrview.svg" --out "$master" >/dev/null
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/Astrview.icns"
/usr/bin/codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
