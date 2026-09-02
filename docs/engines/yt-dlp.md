# yt-dlp

- Purpose: inspect and download user-selected media URLs
- Version: detected and tested at 2026.8.19; not bundled
- Status: separately installed Homebrew companion at `/opt/homebrew/bin/yt-dlp`
- Behavior: runs locally and connects directly to the requested source over the network
- Inputs: validated HTTP and HTTPS URLs supported by the installed yt-dlp version
- Outputs: media files in Nodebay-managed local storage or the configured download directory
- Permissions: network and selected-directory access; browser cookies are off by default
- Failure: job becomes failed or cancelled; Nodebay remains open and preserves completed items
- Diagnostics: bounded status and stderr without cookies or arbitrary arguments
- Source: https://github.com/yt-dlp/yt-dlp
- License: Unlicense core with distribution-dependent components; PyInstaller builds can be GPLv3+

yt-dlp and supported sites do not endorse Nodebay. Users are responsible for permissions, copyright, and service terms.
