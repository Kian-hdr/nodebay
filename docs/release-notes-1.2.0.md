# Nodebay 1.2.0 for Apple Silicon

Nodebay 1.2.0 adds optional Quick Chat, available media-source tabs and refinements
to the file drawer. Apple Silicon and macOS 15 or later remain required.

- **Quick Chat:** opt-in OpenAI API or supported Codex CLI, Keychain storage for
  API keys, temporary conversations, configurable expiry and separately consented
  Knowledge Folder excerpts. API billing is separate from ChatGPT subscriptions.
  Replies arrive as complete messages. The key entry has a visible heading,
  bordered secure field and paste instructions. Missing setup is shown explicitly.
- **Chat layout:** right-aligned question bubbles fit their text and stay compact
  after resizing, with wrapping preserved for long and multiline messages.
- **Media:** switch directly between available sources, including paused media;
  more space above the title; cleared unavailable metadata; corrected QuickTime
  document selection.
- **File drawer:** stable Finder-file intake, drag feedback and persistent
  downloaded files ready to drag into another app.
- **Optional Longhaul companion:** acknowledged automatic-protection controls
  and support for its Nodebay/Menu Bar location preference. Longhaul is separately
  installed and paired, is not bundled, and has no public installer configured.

The integrated local suite passed all 198 tests in 142.163 seconds after the key
field and bubble fixes. The signed Apple Silicon Release build was installed and
visually checked. A native chat using `gpt-5-mini` answered the synthetic prompt
**Reply exactly OK.** with **OK**, using the existing saved key and no Knowledge
Folder. Regression coverage includes short and multiline text, emoji, Arabic,
long wrapping and resizing. The final DMG and ZIP are Developer ID signed,
notarized and stapled, with matching checksums. Installation and real API chat
passed from the final DMG, preserving existing managed data and AI settings.
[GitHub CI](https://github.com/Kian-hdr/nodebay/actions/runs/34044567111) passed
for the exact application-source commit. Anonymous hosted downloads match their checksums. The Homebrew upgrade and
non-zap reinstall passed on the same Mac, including preserved data/settings and
a real API reply after reinstall. Other supported macOS versions, every
accessibility/display configuration, Knowledge Folder retrieval and physical
sleep behavior were not fully tested.
See the [verification matrix](https://github.com/Kian-hdr/nodebay/blob/main/docs/release-verification-matrix.md) for current evidence.

The release is available from [GitHub Releases](https://github.com/Kian-hdr/nodebay/releases/tag/nodebay-v1.2.0)
and the `Kian-hdr/nodebay` Homebrew tap. The [setup prompt](https://github.com/Kian-hdr/nodebay/blob/nodebay-v1.2.0/SETUP-PROMPT.md)
preserves existing installations and guides secure, optional configuration.

Nodebay remains GPL-3.0 software based on Boring Notch. Required notices are in
the source repository and included in release packages.
