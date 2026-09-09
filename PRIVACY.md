# Nodebay privacy

Nodebay has no analytics service, advertising SDK, proxy, download server, or Nodebay cloud account. Shelf files, stacks, preferences, conversions, compression jobs, and processing logs stay on the Mac. Routine diagnostics retain bounded engine output and do not include converted document contents.

## Network activity

Network access occurs only when a feature inherently needs it:

- Quick Chat is off by default. In Codex CLI mode, submitted chat text goes to OpenAI through the user's existing Codex sign-in. In OpenAI API mode, submitted chat text goes directly to the OpenAI Responses API and uses separate API billing. API keys are stored in macOS Keychain, never preferences or logs. The explicit connection test sends only a short synthetic prompt. Nodebay does not continuously contact either provider while Quick Chat is off.
- yt-dlp connects directly from the Mac to a media URL selected by the user. Browser-cookie access is disabled by default.
- Lyrics can query the public `lrclib.net` API when the user enables lyrics.
- Media artwork can be fetched from the artwork URL supplied by the selected playback source.
- Links opened by the user are handed to the default browser.

Microsoft MarkItDown conversion and ImageOptim compression are local-only. The MarkItDown XPC environment removes proxy variables and sets the bundled runtime to local-only mode.

The optional Browser Media Bridge is also local-only. Its explicitly installed Chrome extension can access media elements only on `www.youtube.com` and `music.youtube.com`. It sends Nodebay a tab identifier, visible media title and artist, playback state and timing, volume, and supported-control flags through Chrome native messaging and a loopback-only connection. It does not request browser history, cookies, broad tab-list access, web-request access, clipboard access, or access to other sites. Nodebay does not send this browser media data to a server.

## Local equalizer

Spotify, QuickTime Player and identified Chrome audio are processed locally through Core Audio process taps after this Mac grants System Audio Recording permission. Nodebay does not record, save or upload the tapped audio. A nonmuting startup probe verifies audio before routing the processed output; bypass and failure restore normal playback. Chrome processing can affect other audible Chrome tabs because its audio is process-scoped. Local shelf audio uses AVAudioEngine and does not require external-app recording permission.

## Quick Chat (introduced in 1.2.0)

Quick Chat is not included in version 1.1.0. It requires an explicit provider
choice in **AI & Quick Chat** settings. Submitted questions and the
temporary conversation context go to OpenAI; it is not offline inference. API
connection validation sends a short synthetic prompt and can incur API usage.

Nodebay keeps the chat and draft in memory, rather than saved chat files or
preferences. Closing the notch preserves them until the configured inactivity
timeout; the default is three hours. New Chat, changing provider, turning Quick
Chat off, expiry or quitting clears Nodebay's temporary conversation. The API
request uses an ephemeral URL session, supplies no remote tools, and sets
`store: false`. These local and request-level controls do not establish
provider-wide deletion. Retention is governed by the selected provider and
account. Copy Context is an explicit user action.

Choosing a Knowledge Folder grants local read-only access. Separate consent is
required before matching excerpts can be included in a submitted question.
When enabled for that question, Nodebay searches locally and sends up to four
small matching passages, their relative paths and citation metadata with the
question through the selected provider. It does not upload the full folder.
Disable cloud excerpts or disconnect the folder in settings to stop including
passages in future questions; this does not recall earlier provider requests.

The API key is stored as a this-device-only macOS Keychain item. It is not placed
in preferences or routine logs. It can be replaced or removed from the API
settings. API usage and billing are separate from a ChatGPT subscription.

## Optional Longhaul companion

Longhaul remains a separate local app and is not bundled or installed by Nodebay.
No public Longhaul installer is configured. Explicit pairing is required. The
local authenticated connection reports generic supported-job status and measured
progress; it does not send input paths, URLs, document contents or command
arguments. Longhaul owns sleep protection and battery policy. An enabled
automation setting is not proof of an active power assertion.

## Files and permissions

Nodebay stores references and security-scoped bookmarks for shelf files and selected output folders. Removing a tile or dissolving a stack removes only Nodebay's reference. It does not delete the original file. Generated files use collision-safe names.

Calendar, camera, microphone, Accessibility, Apple Events, and folder access are requested only for features that need them. Each can be disabled in Nodebay or macOS Settings. Accessibility is needed only for system HUD replacement and related controls.

## Updates

Nodebay 1.2.1 adds Sparkle updates from a Nodebay-owned HTTPS feed hosted on GitHub. The feed and downloaded archives require Nodebay's Ed25519 signatures; the application also carries its Developer ID signature. Nodebay never uses the original Boring Notch appcast. A first-run choice controls automatic checks and downloads; manual checking is available in About Nodebay. These choices can be changed later.

An update check sends an ordinary HTTPS request to GitHub's raw-content service, and downloading an update contacts GitHub Releases and its download infrastructure. These services receive normal connection information such as the requesting IP address. Sparkle system profiling and JavaScript release notes are disabled. Update requests do not include your API key, chat messages, shelf contents or original files. See [update setup and migration](docs/features/updates.md). Homebrew remains an alternative update method.

Quick Notes reads copied content only after an explicit paste or New Note action, processes it locally, and retains only the resulting Markdown file. There is no continuous clipboard monitoring or content logging. Markdown Quick Look is sandboxed with no network entitlement and never loads remote resources. STL Repair passes a temporary copy to the separately installed Blender companion with network access denied; originals are never supplied for modification.
