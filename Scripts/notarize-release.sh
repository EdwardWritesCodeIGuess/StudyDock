#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Developer ID Application certificate name.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"
if [[ "$CODE_SIGN_IDENTITY" != "Developer ID Application: "* ]]; then
    echo "Set CODE_SIGN_IDENTITY to the full Developer ID Application certificate name." >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -F -- "\"$CODE_SIGN_IDENTITY\"" >/dev/null; then
    echo "The Developer ID Application identity and private key must be available in Keychain." >&2
    exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
bash Scripts/build-mac.sh
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}StudyDock-notarize.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/StudyDock.app"
ditto --norsrc --noextattr build/StudyDock.app "$APP"
codesign --verify --deep --strict "$APP"
notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$2"
    python3 - "$2" <<'JSONCHECK'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
if result.get('status') != 'Accepted':
    sys.exit('Apple did not accept this submission. Review ' + sys.argv[1] + ' and the notarytool log before distributing.')
print('Apple notarization accepted: ' + result['id'])
JSONCHECK
}
ditto -c -k --keepParent "$APP" "$STAGING/submission.zip"
notarize "$STAGING/submission.zip" build/notarization-app.json
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
ditto -c -k --keepParent "$APP" build/StudyDock-notarized.zip
ln -s /Applications "$STAGING/Applications"
printf 'Drag StudyDock into Applications, eject this disk, then open StudyDock from Applications.\n' > "$STAGING/Install.txt"
rm "$STAGING/submission.zip"
hdiutil create -volname StudyDock -srcfolder "$STAGING" -ov -format UDZO build/StudyDock-notarized.dmg
codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" build/StudyDock-notarized.dmg
notarize build/StudyDock-notarized.dmg build/notarization-dmg.json
xcrun stapler staple build/StudyDock-notarized.dmg
xcrun stapler validate build/StudyDock-notarized.dmg
spctl --assess --type open --context context:primary-signature --verbose build/StudyDock-notarized.dmg
(cd build && shasum -a 256 StudyDock-notarized.dmg StudyDock-notarized.zip > StudyDock-notarized-SHA256SUMS.txt)
echo "Verified notarized downloads are in build/. Publish only these files."
