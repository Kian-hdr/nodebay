#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
imageoptim="/Applications/ImageOptim.app/Contents/MacOS/ImageOptim"
fixture="$project_root/Design/NodebayIcon/Nodebay-AppIcon-1024.png"

if [[ ! -x "$imageoptim" ]]; then
    print -u2 "ImageOptim is unavailable at /Applications/ImageOptim.app."
    exit 2
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/nodebay-imageoptim-test.XXXXXX")
cleanup() {
    if [[ "$test_root" == "${TMPDIR:-/tmp}"/nodebay-imageoptim-test.* && -d "$test_root" ]]; then
        /bin/rm -rf "$test_root"
    fi
}
trap cleanup EXIT

source_image="$test_root/source.png"
optimized_copy="$test_root/source-optimized.png"
/bin/cp "$fixture" "$source_image"
/bin/cp "$source_image" "$optimized_copy"

source_hash_before=$(/usr/bin/shasum -a 256 "$source_image" | /usr/bin/awk '{print $1}')
source_size=$(/usr/bin/stat -f %z "$source_image")

if ! "$imageoptim" "$optimized_copy" >"$test_root/imageoptim.log" 2>&1; then
    print -u2 "ImageOptim failed while processing the safe copy."
    /usr/bin/tail -40 "$test_root/imageoptim.log" >&2
    exit 1
fi

source_hash_after=$(/usr/bin/shasum -a 256 "$source_image" | /usr/bin/awk '{print $1}')
optimized_size=$(/usr/bin/stat -f %z "$optimized_copy")

[[ "$source_hash_before" == "$source_hash_after" ]] || {
    print -u2 "ImageOptim source-preservation test failed."
    exit 1
}
/usr/bin/sips -g pixelWidth -g pixelHeight "$optimized_copy" >/dev/null

print "ImageOptim copy-first fixture passed"
print "Source unchanged: $source_hash_after"
print "Original bytes: $source_size"
print "Optimized bytes: $optimized_size"
