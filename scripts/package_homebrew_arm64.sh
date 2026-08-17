#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
release_version=${RELEASE_VERSION:-2.8-beta.0-markitdown.1}
release_tag=${RELEASE_TAG:-markitdown-v$release_version}
build_root="$project_root/build/homebrew-arm64-release"
derived_data="$build_root/DerivedData"
artifact_name="boringNotch-MarkItDown-$release_version-arm64.zip"
artifact_path="$build_root/$artifact_name"
app_source="$derived_data/Build/Products/Release/boringNotch.app"

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
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/boringnotch-homebrew-stage.XXXXXX")
trap 'rm -rf "$stage_root"' EXIT
app_stage="$stage_root/boringNotch.app"

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
cp "$project_root/LICENSE" "$licenses_root/BoringNotch-GPL-3.0.txt"
cp "$project_root/THIRD_PARTY_LICENSES" "$licenses_root/BoringNotch-Third-Party-Licenses.txt"
cp "$project_root/THIRD_PARTY_LICENSES_MARKITDOWN" "$licenses_root/MarkItDown-Runtime-Notices.txt"

cat > "$licenses_root/SOURCE_AND_LICENSES.txt" <<EOF
Boring Notch MarkItDown Edition $release_version

Corresponding source and build instructions:
https://github.com/Kian-hdr/boring.notch/tree/$release_tag

Boring Notch is distributed under GPL-3.0. Microsoft MarkItDown 0.1.7 is
bundled unmodified under the MIT License. Complete notices are included in this
directory and in the bundled MarkItDown runtime.
EOF

xattr -cr "$app_stage"
codesign --force --deep --sign - "$app_stage"
codesign --verify --deep --strict "$app_stage"

main_arch=$(file "$app_stage/Contents/MacOS/boringNotch")
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
