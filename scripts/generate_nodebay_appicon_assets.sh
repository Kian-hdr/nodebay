#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
source_png="$project_root/Design/NodebayIcon/Nodebay-AppIcon-1024.png"
asset_dir="$project_root/boringNotch/Assets.xcassets/AppIcon.appiconset"

[[ -f "$source_png" ]] || { print -u2 "Missing Icon Composer export: $source_png"; exit 2; }

for pixels in 16 32 64 128 256 512 1024; do
  /usr/bin/sips -z "$pixels" "$pixels" "$source_png" --out "$asset_dir/nodebay-$pixels.png" >/dev/null
done
/bin/cp "$source_png" "$project_root/boringNotch/Assets.xcassets/logo2.imageset/Nodebay-AppIcon-1024.png"

print "Generated Nodebay app icon assets from the checked-in Icon Composer export"
