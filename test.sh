#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mkdir -p "$root/build/module-cache" "$root/build/mock-project/.venv/bin"
touch "$root/build/mock-project/.astrbot"
install -m 755 "$root/Tests/mock-astrbot.py" "$root/build/mock-project/.venv/bin/astrbot"
xcrun --sdk macosx swiftc -D ASTRVIEW_TEST -swift-version 5 \
    -module-cache-path "$root/build/module-cache" -framework AppKit -framework WebKit \
    "$root/Sources/AstrviewApp.swift" "$root/Sources/BotProcess.swift" "$root/Sources/WorkspaceView.swift" "$root/Sources/LaunchPanel.swift" \
    "$root/Tests/Smoke.swift" -o "$root/build/AstrviewSmoke"
"$root/build/AstrviewSmoke" "$root/build/mock-project"
