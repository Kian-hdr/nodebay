# Nodebay 1.2.0 for Apple Silicon

**Draft, unpublished.** Real OpenAI API connection validation and native chat
passed, and the key field and compact message bubble were visually verified.
Final clean-source packaging, notarization and Homebrew validation remain pending.
This file must be reconciled with the completed release evidence before publishing.

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
long wrapping and resizing. These checks do not establish final artifact
validation, all supported macOS versions, every accessibility/display
configuration, Knowledge Folder retrieval or physical sleep behavior.
See the [verification matrix](release-verification-matrix.md) for current evidence.

The existing public release is available from [GitHub Releases](https://github.com/Kian-hdr/nodebay/releases/latest)
and the `Kian-hdr/nodebay` Homebrew tap. The [setup prompt](../SETUP-PROMPT.md)
preserves existing installations and guides secure, optional configuration.

Nodebay remains GPL-3.0 software based on Boring Notch. Required notices are in
the source repository and included in release packages.
