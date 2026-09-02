# MP4 video compression

Available in Nodebay 1.0.0 and later.

Drop a local `.mp4` file into Nodebay's file drawer and click **Compress Video**.
The same command is available under **Video Actions** in the file's context menu.
During processing the button becomes **Cancel Compression**.

Nodebay uses the separately installed FFmpeg companion, tested with FFmpeg 9.0.1
and its libx264 encoder. Install it with `brew install ffmpeg` if engine diagnostics
report it missing. No new runtime is bundled and no engine source is modified.

## Output and safety

- Lossy H.264 video (CRF 26, medium preset, 8-bit 4:2:0), fitted within 1920 × 1080
  without upscaling; aspect ratio and frame timing are retained.
- First video track and optional first audio track (AAC, 128 kb/s). Additional
  tracks, subtitles, chapters, and source metadata are omitted from the copy.
- SDR only. PQ/HLG HDR is rejected rather than silently changing its colors.
- The original remains unchanged. Only a staged copy is passed to FFmpeg, with
  local-file-only input protocols and structured arguments, never a shell.
- The result is named `original-name-compressed.mp4` in a unique directory under
  Nodebay's Application Support/Generated Videos folder. It is inserted beside
  the source tile and stays an ordinary draggable file across relaunches.
- Removing a result tile removes its reference, not the generated disk file.
- A size comparison is shown. Already efficient videos may not get smaller;
  Nodebay then offers **Discard Copy** (default) or **Keep Copy**.
- One video is encoded at a time with bounded threads and a one-hour timeout.
  Cancellation/failure cleans only the job's temporary data and unretained output.
- Free local storage is needed for a source copy and encoded output. Large files
  can take time to stage before FFmpeg starts. There is no percentage estimate;
  the shelf shows indeterminate activity and cancellation.

## Verification

`python3 -m unittest discover -s tests -p 'test_nodebay_video_compression.py' -v`
compiles the production Swift service with an isolated process adapter and runs
real FFmpeg on generated fixtures. It covers video/audio decoding, portrait/silent
input, source checksums, duplicate names, malformed input, engine failure,
cancellation cleanup, concurrency rejection, no reduction, HDR rejection, unusual
filenames, and non-overwriting local-only arguments. These service tests do not
substitute for the installed app's sandbox/XPC and UI checks.

FFmpeg's applicable license depends on the installed build. See
[engine notices](../engines/ffmpeg.md). Nodebay is not affiliated with or endorsed
by FFmpeg. Argument behavior follows the [official FFmpeg documentation](https://ffmpeg.org/ffmpeg.html).
