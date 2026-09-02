# Native Markdown Quick Look

Finder can render `.md` and `.markdown` files using the Quick Look extension
embedded in Nodebay. Select a file and press Space. The main application does
not need to be running. Nodebay's Shelf continues to use its existing native
Quick Look path; no keyboard interception was added for this feature.

## Appearance contract

The reference is Finder's actual `.txt` preview on macOS 26.6.2, not a mockup.
macOS owns the window, title, controls, materials, resizing, and dismissal.
The extension supplies a transparent `NSScrollView` and non-editable, selectable
`NSTextView`. Both have `drawsBackground = false`. There is **no additional
background layer, blur, rounded document surface, toolbar, or branding**.

Kian explicitly approved this translucent appearance on 2026-09-03. Preserve it.
Reduce Transparency is handled by the Quick Look host; no custom replacement
surface is necessary. Text uses adaptive AppKit colors and system fonts.

Apple's built-in text renderer has a rounded, opaque document inset. Its private
layout is not a public Quick Look API, and duplicating it would conflict with the
approved transparent design. Markdown body text uses the proportional system
font; code uses the system monospaced font. Headings and paragraph spacing are
content formatting, not replacement window chrome.

## Rendering and privacy

`Packages/NodebayMarkdown` is a separate reusable local Swift package. It uses
Foundation's full Markdown parser and converts presentation intents into AppKit
text attributes and native text tables. No third-party parser is added.

Supported: headings, paragraphs, emphasis, ordered/unordered/nested lists,
task checkboxes, blockquotes, links, tables, and fenced code. Code receives
restrained keyword-weight emphasis, not a full language-specific syntax parser.
Task checkboxes are read-only text, as expected for a preview.

Images display their alt text. HTML is never executed. Image URLs, local image
files, stylesheets, scripts, fonts, and other resources are not loaded. Links
remain selectable/copyable but do not navigate from the extension. There is no
WebKit, cloud service, telemetry, or document-content logging. The sandbox has
read-only user-selected file access and **no network entitlement**.

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
repository license. AppKit, Foundation, Quartz and Quick Look are operating-system
frameworks, not redistributed third-party engines. Existing third-party notices
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
