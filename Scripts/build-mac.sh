#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARGS=()
if [[ -n "${STUDYDOCK_SDK:-}" ]]; then
  BUILD_ARGS+=(--sdk "$STUDYDOCK_SDK" --build-system native)
fi
swift build -c release "${BUILD_ARGS[@]}"
APP="build/StudyDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_PATH=$(swift build -c release "${BUILD_ARGS[@]}" --show-bin-path)
cp "$BIN_PATH/StudyDock" "$APP/Contents/MacOS/StudyDock"
cp Configuration/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.edwardlink.StudyDock' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable StudyDock' "$APP/Contents/Info.plist"
if [[ -f Resources/StudyDock.icns ]]; then
  cp Resources/StudyDock.icns "$APP/Contents/Resources/StudyDock.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string StudyDock' "$APP/Contents/Info.plist"
fi
# Ad hoc signing runs on this Mac. Distribution requires your Developer ID.
xattr -cr "$APP"
codesign --force --sign - --entitlements Configuration/StudyDock.entitlements "$APP"
printf 'Built %s/build/StudyDock.app\n' "$PWD"
