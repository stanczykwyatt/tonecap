#!/bin/bash
# Builds a universal "Tonecap.app" (Apple silicon and Intel) into ./build and signs it.
#
#   scripts/build-app.sh            ad-hoc signature, for running on this Mac
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:--}"
# A Developer ID build needs a secure timestamp to be notarized; an ad-hoc one can't have one.
timestamp="--timestamp=none"
if [[ "$identity" != "-" ]]; then
	timestamp="--timestamp"
fi
app="build/Tonecap.app"

# Each architecture is built on its own and then combined, which works with just the
# Command Line Tools. Building both in one step needs Xcode.
binaries=()
for arch in arm64 x86_64; do
	triple="$arch-apple-macosx14.0"
	swift build -c release --product Tonecap --triple "$triple"
	bin="$(swift build -c release --triple "$triple" --show-bin-path)"
	binaries+=("$bin/Tonecap")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Tonecap"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
	cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi

# No entitlements at all: Input Monitoring, the one permission it asks for, needs none, and it has
# no network entitlement because it never connects to anything (see SECURITY.md).
# The hardened runtime keeps other code from being loaded into it.
# Signed with the default requirement, which names this exact build. macOS ties Input Monitoring
# to it, so no other program can claim the permission by reusing the bundle ID. The cost is that
# each update has to be allowed again. A Developer ID signature would keep it across updates.
codesign --force --options runtime "$timestamp" --sign "$identity" "$app"
codesign --verify --strict "$app"

echo "Built $app"
