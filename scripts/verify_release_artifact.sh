#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
artifact=${1:-$project_root/build/nodebay-homebrew-arm64-release/Nodebay-0.1.0-arm64.zip}
require_notarized=${REQUIRE_NOTARIZED:-0}

[[ -f "$artifact" ]] || {
    print -u2 "Release archive not found: $artifact"
    exit 1
}

verify_root=$(mktemp -d "${TMPDIR:-/tmp}/nodebay-release-verify.XXXXXX")
trap 'rm -rf "$verify_root"' EXIT
ditto -x -k "$artifact" "$verify_root"
app="$verify_root/Nodebay.app"
helper="$app/Contents/XPCServices/BoringNotchXPCHelper.xpc"
runtime="$app/Contents/Resources/markitdown-runtime"
licenses="$app/Contents/Resources/Licenses"

[[ -d "$app" && -d "$helper" && -d "$runtime" ]] || {
    print -u2 "The archive does not contain the expected Nodebay layout."
    exit 1
}

codesign --verify --deep --strict "$app"

app_entitlements=$(codesign -d --entitlements :- "$app" 2>/dev/null)
helper_entitlements=$(codesign -d --entitlements :- "$helper" 2>/dev/null)
if print -r -- "$app_entitlements$helper_entitlements" | grep -q 'com.apple.security.get-task-allow'; then
    print -u2 "Release artifact contains the debug get-task-allow entitlement."
    exit 1
fi

for executable in \
    "$app/Contents/MacOS/Nodebay" \
    "$runtime/markitdown-local"; do
    file "$executable" | grep -q 'Mach-O 64-bit executable arm64' || {
        print -u2 "Non-arm64 executable: $executable"
        exit 1
    }
done

for notice in \
    Nodebay-GPL-3.0.txt \
    Boring-Notch-Foundation-Notices.txt \
    MarkItDown-Runtime-Notices.txt \
    Nodebay-Third-Party-Notices.md \
    Nodebay-Privacy.md \
    SOURCE_AND_LICENSES.txt; do
    [[ -s "$licenses/$notice" ]] || {
        print -u2 "Missing release notice: $notice"
        exit 1
    }
done

if [[ "$require_notarized" == "1" ]]; then
    spctl --assess --type execute --verbose=4 "$app"
    xcrun stapler validate "$app"
fi

print "Developer ID signature: passed"
print "Debug entitlement exclusion: passed"
print "Apple Silicon architecture: passed"
print "Bundled notices: passed"
if [[ "$require_notarized" == "1" ]]; then
    print "Gatekeeper and staple validation: passed"
else
    print "Gatekeeper and staple validation: skipped (set REQUIRE_NOTARIZED=1 after notarization)"
fi
shasum -a 256 "$artifact"
