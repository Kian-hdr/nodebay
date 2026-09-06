#!/bin/bash
# Local build/run only. No packaging, notarization, or publication.
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in
    run|--verify|--build-only) ;;
    *) echo "usage: $0 [run|--verify|--build-only]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Documents may be synchronized by iCloud; keep build products outside it.
DERIVED_DATA="${NODEBAY_DERIVED_DATA:-$HOME/Library/Caches/Nodebay/DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/Nodebay.app"
# Maintainer defaults preserve local permission continuity. Other contributors
# can supply their own identity/team; optional Longhaul peer trust still requires
# its documented matching signatures. No signing credentials are included here.
NODEBAY_SIGNING_IDENTITY="${NODEBAY_SIGNING_IDENTITY:-Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)}"
NODEBAY_DEVELOPMENT_TEAM="${NODEBAY_DEVELOPMENT_TEAM:-HZWY8HT54D}"
if [[ "$MODE" != --build-only ]]; then
    pkill -x Nodebay || true
fi
xcodebuild -project "$ROOT_DIR/boringNotch.xcodeproj" -scheme boringNotch \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$NODEBAY_SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$NODEBAY_DEVELOPMENT_TEAM" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES build
codesign --verify --deep --strict "$APP_BUNDLE"
if [[ "$MODE" != --build-only ]]; then
    /usr/bin/open -n "$APP_BUNDLE"
    if [[ "$MODE" == --verify ]]; then
        sleep 1
        pgrep -x Nodebay
    fi
fi
