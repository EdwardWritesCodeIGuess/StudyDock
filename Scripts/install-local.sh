#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x StudyDock >/dev/null; then
    echo "Quit StudyDock before installing a replacement." >&2
    exit 1
fi
if [ ! -w /Applications ]; then
    echo "Applications is not writable. Ask your Mac administrator to install this build." >&2
    exit 1
fi
bash Scripts/build-mac.sh
STAGING="$(mktemp -d /Applications/.StudyDock-install.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
ditto --norsrc --noextattr build/StudyDock.app "$STAGING/StudyDock.app"
codesign --verify --deep --strict "$STAGING/StudyDock.app"
if pgrep -x StudyDock >/dev/null; then
    echo "StudyDock opened during the build. Quit it before installing the replacement." >&2
    exit 1
fi
BACKUP=""
if [ -e /Applications/StudyDock.app ]; then
    BACKUP="build/local-backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    mv /Applications/StudyDock.app "$BACKUP/StudyDock.app"
    echo "Previous app saved in $PWD/$BACKUP"
fi
if ! mv "$STAGING/StudyDock.app" /Applications/StudyDock.app; then
    if [ -n "$BACKUP" ]; then
        mv "$BACKUP/StudyDock.app" /Applications/StudyDock.app
    fi
    exit 1
fi
open /Applications/StudyDock.app
echo "Installed and opened /Applications/StudyDock.app"
