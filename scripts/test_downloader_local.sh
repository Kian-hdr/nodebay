#!/bin/zsh
set -euo pipefail

yt_dlp_path=${YT_DLP_PATH:-/opt/homebrew/bin/yt-dlp}
ffmpeg_path=${FFMPEG_PATH:-/opt/homebrew/bin/ffmpeg}
fixture_dir=$(/usr/bin/mktemp -d /tmp/nodebay-downloader-test.XXXXXX)
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    /bin/kill "$server_pid" 2>/dev/null || true
  fi
  if [[ "$fixture_dir" == /tmp/nodebay-downloader-test.* && -d "$fixture_dir" ]]; then
    /bin/rm -rf "$fixture_dir"
  fi
}
trap cleanup EXIT INT TERM

[[ -x "$yt_dlp_path" ]] || { print -u2 "yt-dlp not executable: $yt_dlp_path"; exit 2; }
[[ -x "$ffmpeg_path" ]] || { print -u2 "FFmpeg not executable: $ffmpeg_path"; exit 2; }

"$ffmpeg_path" -v error \
  -f lavfi -i color=c=blue:s=320x180:d=1 \
  -f lavfi -i sine=frequency=440:duration=1 \
  -c:v libx264 -c:a aac -shortest "$fixture_dir/fixture.mp4"
/bin/mkdir "$fixture_dir/output"

port=$(/usr/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
/usr/bin/python3 -m http.server "$port" --bind 127.0.0.1 --directory "$fixture_dir" >"$fixture_dir/server.log" 2>&1 &
server_pid=$!

for attempt in 1 2 3 4 5; do
  /usr/bin/curl -fsS -o /dev/null "http://127.0.0.1:$port/fixture.mp4" && break
  /bin/sleep 0.2
done

common=(--ignore-config --no-config-locations --no-plugin-dirs --no-cookies-from-browser)
metadata=$("$yt_dlp_path" $common --dump-single-json --flat-playlist "http://127.0.0.1:$port/fixture.mp4")
print -r -- "$metadata" | /usr/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["title"] == "fixture"'

"$yt_dlp_path" $common --no-playlist --newline --no-overwrites --restrict-filenames \
  --paths "$fixture_dir/output" \
  --output 'Nodebay-test-%(title).180B-[%(id)s].%(ext)s' \
  --format 'bestvideo*+bestaudio/best' \
  "http://127.0.0.1:$port/fixture.mp4"

output_count=$(/usr/bin/find "$fixture_dir/output" -maxdepth 1 -type f -name 'Nodebay-test-*.mp4' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[[ "$output_count" == "1" ]] || { print -u2 "Expected one downloaded fixture, found $output_count"; exit 1; }

# Exercise MP3 extraction with the saved-quality argument used by Automatic.
"$yt_dlp_path" $common --no-playlist --no-overwrites --restrict-filenames \
  --ffmpeg-location "${ffmpeg_path:h}" \
  --paths "$fixture_dir/output" \
  --output 'Nodebay-audio-%(title).180B-[%(id)s].%(ext)s' \
  --extract-audio --audio-format mp3 --audio-quality 192K \
  "http://127.0.0.1:$port/fixture.mp4"

"${ffmpeg_path:h}/ffprobe" -v error -show_streams -of json \
  "$fixture_dir/output/Nodebay-test-fixture-[fixture].mp4" | /usr/bin/python3 -c \
  'import json,sys; s=json.load(sys.stdin)["streams"]; assert {x["codec_type"] for x in s} == {"video", "audio"}'
"${ffmpeg_path:h}/ffprobe" -v error -show_streams -of json \
  "$fixture_dir/output/Nodebay-audio-fixture-[fixture].mp3" | /usr/bin/python3 -c \
  'import json,sys; s=json.load(sys.stdin)["streams"]; assert len(s)==1 and s[0]["codec_name"]=="mp3"'
"$ffmpeg_path" -v error -i "$fixture_dir/output/Nodebay-test-fixture-[fixture].mp4" -f null -
"$ffmpeg_path" -v error -i "$fixture_dir/output/Nodebay-audio-fixture-[fixture].mp3" -f null -
print "Local MP4 and MP3 downloader fixtures passed; both outputs decoded successfully"
