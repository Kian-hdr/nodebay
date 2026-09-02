#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
artifact=${1:-$project_root/build/nodebay-homebrew-arm64-release/Nodebay-1.0.0-arm64.zip}
require_notarized=${REQUIRE_NOTARIZED:-0}
expected_version=${EXPECTED_VERSION:-1.0.0}
expected_build=${EXPECTED_BUILD:-21}
expected_team=${EXPECTED_TEAM:-HZWY8HT54D}
expected_identifier=${EXPECTED_IDENTIFIER:-theboringteam.boringnotch}

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

generated_conflict=$(/usr/bin/find "$app" \
    \( -name '* 2' -o -name '__pycache__' -o -name '*.pyc' \) -print -quit)
if [[ -n "$generated_conflict" ]]; then
    print -u2 "Generated conflict duplicate in release: ${generated_conflict#$app/}"
    exit 1
fi

unexpected_top_level=(${verify_root}/*(N:t))
if (( ${#unexpected_top_level} != 1 )) || [[ "${unexpected_top_level[1]}" != "Nodebay.app" ]]; then
    print -u2 "The archive must contain only Nodebay.app at its top level."
    exit 1
fi

codesign --verify --deep --strict "$app"

signature_details=$(codesign -dv --verbose=4 "$app" 2>&1)
print -r -- "$signature_details" | grep -Fq "Authority=Developer ID Application: Kian Konrad Tajbakhsh ($expected_team)" || {
    print -u2 "Unexpected or missing Developer ID signing authority."
    exit 1
}
print -r -- "$signature_details" | grep -Fq '(runtime)' || {
    print -u2 "The hardened runtime flag is missing."
    exit 1
}

designated_requirement=$(codesign -d -r- "$app" 2>&1)
print -r -- "$designated_requirement" | grep -Fq "identifier \"$expected_identifier\"" || {
    print -u2 "The designated requirement has the wrong bundle identifier."
    exit 1
}
print -r -- "$designated_requirement" | grep -Fq "certificate leaf[subject.OU] = $expected_team" || {
    print -u2 "The designated requirement has the wrong signing team."
    exit 1
}

actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$actual_version" == "$expected_version" && "$actual_build" == "$expected_build" ]] || {
    print -u2 "Unexpected release metadata: version $actual_version, build $actual_build."
    exit 1
}

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

while IFS= read -r candidate; do
    /usr/bin/file -b "$candidate" | /usr/bin/grep -q 'Mach-O' || continue
    nested_signature=$(codesign -dv --verbose=4 "$candidate" 2>&1) || {
        print -u2 "Unsigned nested Mach-O: ${candidate#$app/}"
        exit 1
    }
    print -r -- "$nested_signature" | grep -Fq "TeamIdentifier=$expected_team" || {
        print -u2 "Nested Mach-O has the wrong signing team: ${candidate#$app/}"
        exit 1
    }
    print -r -- "$nested_signature" | grep -Fq '(runtime)' || {
        print -u2 "Nested Mach-O lacks hardened runtime: ${candidate#$app/}"
        exit 1
    }
    print -r -- "$nested_signature" | grep -Fq 'Timestamp=' || {
        print -u2 "Nested Mach-O lacks a secure timestamp: ${candidate#$app/}"
        exit 1
    }
done < <(/usr/bin/find "$app/Contents" -type f -print)

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
print "Stable designated requirement: passed"
print "Hardened runtime: passed"
print "Release metadata: $actual_version ($actual_build)"
print "Archive contents: Nodebay.app only"
print "Generated conflict duplicates: none"
print "Debug entitlement exclusion: passed"
print "Apple Silicon architecture: passed"
print "Nested code signing and timestamps: passed"
print "Bundled notices: passed"
if [[ "$require_notarized" == "1" ]]; then
    print "Gatekeeper and staple validation: passed"
else
    print "Gatekeeper and staple validation: skipped (set REQUIRE_NOTARIZED=1 after notarization)"
fi
shasum -a 256 "$artifact"
