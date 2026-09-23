# Native Markdown Quick Look

Finder can render `.md` and `.markdown` files using the Quick Look extension
embedded in Nodebay. Select a file and press Space. The main application does
not need to be running. Nodebay's Shelf continues to use its existing native
Quick Look path; no keyboard interception was added for this feature.

## Appearance contract

In **Settings → Appearance → Markdown Preview**, turn **Use solid background**
on for a gray reading surface, or off for the existing Liquid Glass appearance.
The default for new installs is on; an existing saved choice is preserved. Close and reopen Quick Look after changing the setting.
The choice is shared with the extension, so it also works when Nodebay is quit.

macOS continues to own the preview window, title, controls, materials, resizing
and dismissal. The extension supplies a non-editable, selectable `NSTextView`
in an `NSScrollView`. Glass mode leaves both transparent. Solid mode fills the
scroll view with adaptive `NSColor.windowBackgroundColor`, including the empty
area below short documents; the text view stays transparent. The surface follows
Light/Dark appearance rather than hard-coding a gray value. Reduce Transparency
uses the solid surface regardless of the preference. The reading area is continuous;
Apple's private rounded TXT inset layout is not reproduced.

Both signed targets share only this preference using a TeamID-prefixed macOS
App Group and `UserDefaults(suiteName:)`. The group identifier is derived from
`DEVELOPMENT_TEAM` in each target's Info plist and entitlement. No additional document-access entitlement is added. WebKit requires a network-client
entitlement to start its process even for local files; remote resources remain blocked. Text retains adaptive AppKit
colors and system fonts; code uses the system monospaced font.

## Reading layout

The native layout uses 24-point side margins, 20-point page insets, 12-point
separation between independent blocks and 20 points above section headings.
List siblings remain compact while list exits regain the normal block gap.
Code preserves deliberate blank lines without adding paragraph spacing to every
code line. Tables have explicit space before and after their borders.
This is a native adaptation of GitHub/Obsidian reading rhythm, not their web UI.

## Mermaid diagrams

Fenced `mermaid` blocks render locally as static diagrams among the native text.
The preview shows text immediately and inserts diagrams as they finish. Diagrams
use a flat classic style with consistent one-point frames and no shadows or
layered effects. They fit the available line width when the preview is resized, retain their aspect
ratio, and refresh for light/dark appearance. Repeated identical diagrams remain
separate. The main app does not need to be running.

Mermaid 12.0.0 is bundled under MIT with its license and pinned provenance in
`NodebayMarkdownPreview/Mermaid/`. An isolated, nonpersistent WebKit instance
runs only this bundled renderer, converts its SVG to a bounded raster image,
and releases the instance. No document HTML is executed. CSP, network content
blocking and navigation restrictions prevent external resource loading; generated
attachments have no active links or scripts.

Up to 12 diagrams are rendered per preview, with 20,000 characters/300 lines,
200 edges, an 8-second per-diagram timeout and bounded raster output. Invalid,
over-limit or unsupported diagrams show a concise notice and their original
source. Configuration directives/frontmatter and embedded HTML/images are not
supported in previews. Standard Markdown image URLs remain alt text.

## Rendering and privacy

`Packages/NodebayMarkdown` is a separate reusable local Swift package. It uses
Foundation's full Markdown parser and converts presentation intents into AppKit
text attributes and native text tables. No third-party parser is added.

Supported: headings, paragraphs, emphasis, ordered/unordered/nested lists,
task checkboxes, blockquotes, links, tables, and fenced code. Code receives
restrained keyword-weight emphasis, not a full language-specific syntax parser.
Task checkboxes are read-only text, as expected for a preview. Table borders use
one-point adaptive label color for visibility on both reading surfaces. An explicit
outer table border keeps the right edge visible while preserving cell wrapping.

Document images display their alt text. Document HTML is never executed, and
image URLs, local image files and document-provided styles/scripts/fonts are not
loaded. Links remain selectable/copyable but do not navigate from the extension.
Only the bundled Mermaid engine uses isolated WebKit as described above.
There is no cloud service, telemetry or document-content logging. The sandbox has
read-only user-selected file access. Its network-client entitlement is required by
WebKit process startup; the bundled renderer blocks remote requests and navigation.

File reading and parsing occur on a private worker queue. The file handle closes
before presentation. Request identity prevents stale results from replacing newer
content. Sources are never written, renamed, or moved.

Limits: 2 MiB input; Markdown formatting up to 256 KiB; larger accepted files
get a labelled, bounded plain-text preview. Display is capped at 256 Ki characters
for that fallback and 5,000 blocks for formatted text. UTF-8 and BOM-marked UTF-16
are supported; unsupported encodings and inaccessible files show a concise message.

## Compatibility and licensing

The app and extension retain the macOS 15 minimum. Runtime verification on this
Mac does not establish verification on every supported macOS version.
The renderer and extension are Nodebay-authored GPL-3.0-or-later source under the
repository license. AppKit, Foundation, Quartz, WebKit and Quick Look are operating-system
frameworks, not redistributed engines. Mermaid and its MIT license are bundled. Existing third-party notices
remain applicable to the rest of the app.

## Build and tests

Build the existing `boringNotch` scheme; its dependency embeds
`NodebayMarkdownPreview.appex` under `Nodebay.app/Contents/PlugIns`.
The extension identifier deliberately uses the existing stable app prefix:
`theboringteam.boringnotch.MarkdownPreview`.

```sh
swift test --package-path Packages/NodebayMarkdown
python3 -m unittest discover -s tests -v
```

See [verification and comparison screenshots](../markdown-preview-verification.md).

## Activation and reversal

Before installing, inspect `pluginkit -m -A -D -v -p com.apple.quicklook.preview`
and `qlmanage -m plugins`. Do not disable another provider without the owner's
approval. No competing third-party Markdown provider was registered on this Mac
at the start of this task; Apple's plain-text fallback was active.

Install the complete signed app in `/Applications`, not a loose extension.
For local development, explicit registration can use:

```sh
pluginkit -a /Applications/Nodebay.app/Contents/PlugIns/NodebayMarkdownPreview.appex
pluginkit -e use -i theboringteam.boringnotch.MarkdownPreview
```

To disable just this provider and return to the system fallback:

```sh
pluginkit -e ignore -i theboringteam.boringnotch.MarkdownPreview
```

Use `-e default` to remove that user election, or `-e use` to re-enable it.
System Settings → General → Login Items & Extensions → Quick Look also exposes
preview extensions. The user's normal editor/default Open With association is
not changed. Temporary test app registrations should be removed after installation.

## Official references

- [Quick Look preview controller](https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller)
- [File preview preparation](https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller/preparepreviewoffile(at:completionhandler:))
- [Full Foundation Markdown parsing](https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions/interpretedsyntax-swift.enum/full)
- [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
