#!/usr/bin/env bash
# Build a Release Float.app and install it to /Applications so Spotlight and Launchpad find it.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -scheme Float -configuration Release -destination 'platform=macOS' -derivedDataPath build build -quiet

# Sign with a stable identity so macOS privacy grants (e.g. Documents access) survive reinstalls.
# Ad-hoc signatures change every build, so macOS treats each install as a new app and asks again.
# Override with FLOAT_SIGN_IDENTITY; defaults to the first "Apple Development" certificate in the keychain.
APP=build/Build/Products/Release/Float.app
IDENTITY="${FLOAT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  echo "warning: no signing identity found; privacy prompts will reappear after each install" >&2
fi

pkill -x Float 2>/dev/null || true
rm -rf /Applications/Float.app
ditto build/Build/Products/Release/Float.app /Applications/Float.app
echo "Installed /Applications/Float.app"
