#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
release_version=${RELEASE_VERSION:-0.1.0}
release_tag=${RELEASE_TAG:-nodebay-v$release_version}
build_root="$project_root/build/nodebay-homebrew-arm64-release"
derived_data="$build_root/DerivedData"
artifact_name="Nodebay-$release_version-arm64.zip"
artifact_path="$build_root/$artifact_name"
app_source="$derived_data/Build/Products/Release/Nodebay.app"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "This distribution script must run on Apple Silicon."
    exit 1
fi

"$script_dir/build_markitdown_runtime.sh"
"$script_dir/test_markitdown_runtime.sh"

rm -rf "$derived_data"
rm -f "$artifact_path" "$artifact_path.sha256"
mkdir -p "$build_root"

# Stage outside File Provider-managed folders. Those folders can immediately
# restore FinderInfo attributes that invalidate nested code signatures.
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/nodebay-homebrew-stage.XXXXXX")
trap 'rm -rf "$stage_root"' EXIT
app_stage="$stage_root/Nodebay.app"

xcodebuild \
    -project "$project_root/boringNotch.xcodeproj" \
    -scheme boringNotch \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    MARKETING_VERSION="$release_version" \
    CODE_SIGNING_ALLOWED=NO \
    build

ditto "$app_source" "$app_stage"
licenses_root="$app_stage/Contents/Resources/Licenses"
mkdir -p "$licenses_root"
cp "$project_root/LICENSE" "$licenses_root/Nodebay-GPL-3.0.txt"
cp "$project_root/THIRD_PARTY_LICENSES" "$licenses_root/Boring-Notch-Foundation-Notices.txt"
cp "$project_root/THIRD_PARTY_LICENSES_MARKITDOWN" "$licenses_root/MarkItDown-Runtime-Notices.txt"
cp "$project_root/THIRD_PARTY_NOTICES_NODEBAY.md" "$licenses_root/Nodebay-Third-Party-Notices.md"
cp "$project_root/PRIVACY.md" "$licenses_root/Nodebay-Privacy.md"

cat > "$licenses_root/SOURCE_AND_LICENSES.txt" <<EOF
Nodebay $release_version

Corresponding source and build instructions:
https://github.com/Kian-hdr/boring.notch/tree/$release_tag

Nodebay is distributed under GPL-3.0 and is based on Boring Notch commit
44dd999f70493da48209c99e9f873c47f2e55c83. Microsoft MarkItDown 0.1.7 is
bundled unmodified under the MIT License. Companion yt-dlp, FFmpeg, and
ImageOptim installations are not bundled. Complete notices are included here.
EOF

xattr -cr "$app_stage"
codesign --force --deep --sign - "$app_stage"
codesign --verify --deep --strict "$app_stage"

main_arch=$(file "$app_stage/Contents/MacOS/Nodebay")
helper_arch=$(file "$app_stage/Contents/Resources/markitdown-runtime/markitdown-local")
if [[ "$main_arch" != *"arm64"* || "$helper_arch" != *"arm64"* ]]; then
    print -u2 "The app or MarkItDown helper is not an arm64 executable."
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$app_stage" "$artifact_path"
shasum -a 256 "$artifact_path" | tee "$artifact_path.sha256"

print "Artifact: $artifact_path"
print "Tag: $release_tag"
print "$main_arch"
print "$helper_arch"
