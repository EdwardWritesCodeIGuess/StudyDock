#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARGS=()
if [[ -n "${STUDYDOCK_SDK:-}" ]]; then
  BUILD_ARGS+=(--sdk "$STUDYDOCK_SDK" --build-system native)
fi
swift build -c release "${BUILD_ARGS[@]}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}studydock-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/StudyDock.app"
mkdir -p build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_PATH=$(swift build -c release "${BUILD_ARGS[@]}" --show-bin-path)
cp "$BIN_PATH/StudyDock" "$APP/Contents/MacOS/StudyDock"
cp Configuration/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.edwardlink.StudyDock' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable StudyDock' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$APP/Contents/Info.plist"
if [[ -f Resources/StudyDock.icns ]]; then
  cp Resources/StudyDock.icns "$APP/Contents/Resources/StudyDock.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string StudyDock' "$APP/Contents/Info.plist"
fi
# A local build uses ad-hoc signing; set CODE_SIGN_IDENTITY for Developer ID signing.
xattr -cr "$APP"
SIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY:--}" --entitlements Configuration/StudyDock.entitlements)
if [ "${CODE_SIGN_IDENTITY:--}" != "-" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
ditto --norsrc --noextattr "$APP" build/StudyDock.app
printf 'Built %s/build/StudyDock.app\n' "$PWD"
