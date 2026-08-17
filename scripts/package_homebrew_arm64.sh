#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
release_version=${RELEASE_VERSION:-0.1.0}
release_tag=${RELEASE_TAG:-nodebay-v$release_version}
signing_identity=${SIGNING_IDENTITY:--}
development_team=${DEVELOPMENT_TEAM:-}
build_root="$project_root/build/nodebay-homebrew-arm64-release"
artifact_name="Nodebay-$release_version-arm64.zip"
artifact_path="$build_root/$artifact_name"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "This distribution script must run on Apple Silicon."
    exit 1
fi

"$script_dir/build_markitdown_runtime.sh"
"$script_dir/test_markitdown_runtime.sh"

rm -f "$artifact_path" "$artifact_path.sha256"
mkdir -p "$build_root"

# Stage outside File Provider-managed folders. Those folders can immediately
# restore FinderInfo attributes that invalidate nested code signatures.
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/nodebay-homebrew-stage.XXXXXX")
trap 'rm -rf "$stage_root"' EXIT
derived_data="$stage_root/DerivedData"
app_source="$derived_data/Build/Products/Release/Nodebay.app"
app_stage="$stage_root/Nodebay.app"

build_arguments=(
    -project "$project_root/boringNotch.xcodeproj"
    -scheme boringNotch
    -configuration Release
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$derived_data"
    MARKETING_VERSION="$release_version"
)

if [[ "$signing_identity" == "-" ]]; then
    build_arguments+=(CODE_SIGNING_ALLOWED=NO)
else
    [[ -n "$development_team" ]] || {
        print -u2 "DEVELOPMENT_TEAM is required with SIGNING_IDENTITY."
        exit 1
    }
    build_arguments+=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$signing_identity"
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
        DEVELOPMENT_TEAM="$development_team"
        OTHER_CODE_SIGN_FLAGS=--timestamp
    )
fi

xcodebuild "${build_arguments[@]}" build

ditto "$app_source" "$app_stage"
licenses_root="$app_stage/Contents/Resources/Licenses"
mkdir -p "$licenses_root"
cp "$project_root/LICENSE" "$licenses_root/Nodebay-GPL-3.0.txt"
cp "$project_root/THIRD_PARTY_LICENSES" "$licenses_root/Boring-Notch-Foundation-Notices.txt"
cp "$project_root/THIRD_PARTY_LICENSES_MARKITDOWN" "$licenses_root/MarkItDown-Runtime-Notices.txt"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$licenses_root/Nodebay-Third-Party-Notices.md"
cp "$project_root/PRIVACY.md" "$licenses_root/Nodebay-Privacy.md"

cat > "$licenses_root/SOURCE_AND_LICENSES.txt" <<EOF
Nodebay $release_version

Corresponding source and build instructions:
https://github.com/Kian-hdr/nodebay/tree/$release_tag

Nodebay is distributed under GPL-3.0 and is based on Boring Notch commit
44dd999f70493da48209c99e9f873c47f2e55c83. Microsoft MarkItDown 0.1.7 is
bundled unmodified under the MIT License. Companion yt-dlp, FFmpeg, and
ImageOptim installations are not bundled. Complete notices are included here.
EOF

xattr -cr "$app_stage"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_stage"
else
    runtime_root="$app_stage/Contents/Resources/markitdown-runtime"
    while IFS= read -r candidate; do
        if /usr/bin/file -b "$candidate" | /usr/bin/grep -q 'Mach-O'; then
            codesign --force --options runtime --timestamp --sign "$signing_identity" "$candidate"
        fi
    done < <(/usr/bin/find "$runtime_root" -type f -print)

    # License files and refreshed runtime signatures change the resource seal.
    # Preserve the entitlements produced by Xcode while sealing the final app.
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --preserve-metadata=entitlements,requirements,flags,runtime \
        --sign "$signing_identity" \
        "$app_stage"
fi
codesign --verify --deep --strict "$app_stage"

main_arch=$(file "$app_stage/Contents/MacOS/Nodebay")
helper_arch=$(file "$app_stage/Contents/Resources/markitdown-runtime/markitdown-local")
if [[ "$main_arch" != *"arm64"* || "$helper_arch" != *"arm64"* ]]; then
    print -u2 "The app or MarkItDown helper is not an arm64 executable."
    exit 1
fi

ditto -c -k --keepParent "$app_stage" "$artifact_path"
shasum -a 256 "$artifact_path" | tee "$artifact_path.sha256"

print "Artifact: $artifact_path"
print "Tag: $release_tag"
print "Signing identity: $signing_identity"
print "$main_arch"
print "$helper_arch"
