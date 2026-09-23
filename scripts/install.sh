#!/usr/bin/env bash
# Build a Release Float.app and install it to /Applications so Spotlight and Launchpad find it.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -scheme Float -configuration Release -destination 'platform=macOS' -derivedDataPath build build -quiet

pkill -x Float 2>/dev/null || true
rm -rf /Applications/Float.app
ditto build/Build/Products/Release/Float.app /Applications/Float.app
echo "Installed /Applications/Float.app"
