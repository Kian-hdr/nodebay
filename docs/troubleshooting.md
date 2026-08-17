# Troubleshooting

## Accessibility or HUD is unavailable

Use the signed `/Applications/Nodebay.app`, enable Nodebay in System Settings > Privacy & Security > Accessibility, then relaunch. Nodebay checks authorization in its main process. An ad-hoc rebuild may appear as a different executable identity.

## Conversion fails

Open Plugins & Engines and run the MarkItDown health test. Confirm the bundled runtime reports 0.1.7. Scanned or protected files may contain no extractable text. Nodebay preserves the source and reports a recoverable error.

## Downloads fail

Confirm `/opt/homebrew/bin/yt-dlp` and `/opt/homebrew/bin/ffmpeg` exist and inspect the bounded diagnostics. Nodebay ignores shell configuration, browser cookies, plugins, and arbitrary command-line options.

## Image compression is unavailable

Install ImageOptim in `/Applications/ImageOptim.app`. Nodebay sends a copy, never the source, to its documented blocking executable.

## Duplicate app entries

Keep one `/Applications/Nodebay.app` and remove obsolete build or download copies. Homebrew installs exactly one app. Do not delete Nodebay-generated user output files while cleaning application bundles.

## Shelf item will not drag

Verify the source still exists and re-add it if its security-scoped bookmark is stale. Generated files are regular URLs and must remain at their generated path.
