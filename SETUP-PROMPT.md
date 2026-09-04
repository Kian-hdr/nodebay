# Set up Nodebay with your AI agent

Copy the entire block below into an agent that can use files, a terminal, and
optionally the UI **on your Mac**. No placeholders need editing. A browser-only
chat or remote coding container cannot install the app on your computer.

```text
Install and set up Nodebay on my Mac using the official project:
https://github.com/Kian-hdr/nodebay

Carry out the reversible local installation steps with the tools you have. I
authorize downloading and installing this app, while preserving existing settings
and keeping a recoverable backup before replacing an older app. Ask only for
missing choices or actions I must complete. Do not claim to have installed it on
my Mac if your tools operate only in a remote container.

Quote all filesystem paths in commands, especially app names containing spaces.

1. Check this Mac and existing installations.
Inspect the OS version, CPU architecture, existing app version, and whether it is
managed by Homebrew. Current requirements: Apple Silicon and macOS 15 or later.
Check the current official README and release notes in case requirements changed.
Reuse an equal or newer working version; do not downgrade, reset preferences,
delete user data, or overwrite a modified source checkout. If the app is running,
let me finish active work before quitting it for an update.

2. Choose and verify the official installer.
Read https://github.com/Kian-hdr/nodebay/releases/latest and the current README.
Prefer the official release download. If this app is already managed by
Homebrew, use that existing installation method to avoid duplicate installs.
Resolve the actual compatible asset from a published stable release, not GitHub's
automatic source ZIP. Record the tag, exact download URL, and published SHA-256.
Download to a temporary directory with HTTP failures treated as errors. Verify
the downloaded hash against the matching release checksum or GitHub asset digest.
For a DMG, run hdiutil verify and mount it read-only. For a ZIP, check integrity
and extract into a new staging directory while preserving the app bundle.
Verify the enclosed app with codesign --verify --deep --strict and spctl --assess
--type execute. For a signed DMG, also check its signature and Gatekeeper open
assessment. Stop if a checksum, signature, or Gatekeeper check fails or required
verification cannot be performed. Never strip quarantine, disable Gatekeeper,
ad-hoc re-sign a downloaded release, or ask for credentials in chat to bypass it.
If no compatible signed release exists, stop and report that exact blocker;
do not silently use an old release, mirror, source archive, or unsigned binary.

3. Install one copy.
For a verified downloaded app, copy Nodebay.app into /Applications, preserving its
signature and backing up an older copy before replacement. Use the installed
copy, not the mounted image; eject any mounted DMG afterward. Hand administrator
authentication to me in the normal macOS interface if necessary.

If using Homebrew, inspect the official tap https://github.com/Kian-hdr/homebrew-nodebay
and its actual cask URL, checksum, requirements, dependencies, and install hooks
before executing them. The tap command is brew tap Kian-hdr/nodebay; the fully qualified
install target is Kian-hdr/nodebay/nodebay. Use brew install --cask for a new installation
or a targeted brew upgrade --cask for an existing outdated one. Review any extra
dependencies with me before installing them. If my Homebrew version requires
cask trust, consult its current help, explain it, and ask before granting trust
to this specific cask. Do not trust an entire tap, suppress quarantine, install
unrelated upgrades, or run uninstall --zap. If the cask is absent or its URL fails,
use the verified release route above or report the source-build choice if offered.

4. Complete setup and verify actual use.
Open the installed app through Finder or open. Verify its installed version and
bundle identifier (theboringteam.boringnotch), then inspect its visible interface when UI tools
are available. A running process alone is not a successful UI or feature test.
Open Nodebay and verify that its notch or utility panel opens. Reuse existing
preferences. If a Boring Notch installation is present, review the documented
migration first: Nodebay currently shares its bundle identifier. Do not run both
apps or remove either one's data; ask me which app should remain active if unclear.

Ask which optional features I want. The DMG includes the MarkItDown runtime but
does not install the media companions. Media download/conversion uses separately
installed yt-dlp and FFmpeg; the Homebrew cask installs both as dependencies.
Image compression uses the separate ImageOptim app; STL Repair uses the documented
compatible Blender version. Reuse installed companions and install missing ones
from their official sources only for features I select. Do not install Blender,
ImageOptim, or a browser extension merely to prove the base app works.

Guide me through only the permissions needed for selected features. Leave macOS
permission dialogs and Chrome extension loading/enabling to me. Keep browser-cookie
access off unless I explicitly request it. Test with a disposable local file or
harmless note, preserve the original, and check the actual result. Do not download
media, read private browser data, or run repair on my real models as a setup test.

Ask before enabling launch at login. Leave passwords, API keys, account sign-in,
permission approvals, purchases, and paid usage to me through their normal
interfaces. Do not change system-wide security or publish or send anything.

5. Report the result.
Give me the installed path and version, installation method, exact source URL,
checksum/signature results, settings changed, functional checks performed, and
how to open and update the app. Separate installed, configured, and functionally
tested. If a permission, credential, unavailable binary, or tool limitation leaves
setup incomplete, state the smallest remaining action. Do not claim speech,
downloads, hardware behavior, or UI interaction worked unless actually tested.
```

Maintainers: keep this prompt, the README installation section, and the official
release or cask requirements aligned whenever installation or setup changes.
