# Quick Notes

Quick Notes is new in Nodebay 1.1.0. See the verification record for automated coverage and pending physical hover-paste checks.

Open the file shelf, leave the pointer inside the open notch, and press Command-V. Normal text becomes a persistent Markdown file without a confirmation dialog. A brief, dismissible “Quick Note added” message appears and clears after three seconds or when the shelf closes. The shelf scrolls to and selects the new regular Markdown file.

The subtle New Note button opens a small native editor. Its normal text-field paste behavior is preserved. Settings contains a dedicated Quick Notes section for enabling the feature, filename style, optional generic heading names, rich-text preservation, the confirmation, automatic shelf insertion, storage, and redacted diagnostics.

## Deterministic paste routing

1. File-URL clipboard representations use the existing file workflow.
2. Text made entirely of whitespace-separated HTTP/HTTPS URLs uses the downloader. URL credentials and non-HTTP schemes are not sent to the downloader. Supported sites still depend on yt-dlp; Nodebay does not infer site support by downloading during routing.
3. Prose, Markdown, prompts, code, lists, or URLs mixed with other text become notes.
4. Focused Nodebay text editors, empty/unsupported clipboards, other shortcuts, and paste outside an open notch pass through normally. If Quick Notes is disabled, normal text paste is not intercepted.

Hover paste uses the existing Accessibility-authorized event tap. The New Note editor is the fallback when that tap is unavailable. Clipboard contents are read only in response to an eligible explicit paste, never by polling, monitoring clipboard changes, or browsing clipboard history.

## Content and privacy

Plain text and existing Markdown are preserved byte-for-byte except CRLF/CR line endings are normalized to LF. Unicode, emoji, non-English text, paragraph spacing and fenced code remain intact. Processing, parsing and writing run locally outside the main UI actor; the AppKit clipboard snapshot is captured synchronously during the paste event so it cannot be replaced by a later clipboard change.

Text is limited to 1 MiB in UTF-8. HTML and RTF input are limited to 4 MiB per representation; oversized or unreliable rich input falls back to a valid plain-text representation. Larger text is rejected with a recoverable error.

HTML conversion supports a deliberately conservative subset: paragraphs, headings, basic emphasis, lists, blockquotes, links and code. It uses an offline XML parser with external entities disabled, no WebKit/HTML importer, and bounded nesting/output. Unsupported or malformed HTML, tables, embedded images, scripts, and documents with declarations fall back to plain text. RTF conversion preserves basic emphasis; unsupported attachments fall back to plain text. No AI model or external conversion service is involved.

Clipboard data and rendered content are scoped to one operation, not retained in history or diagnostics after it completes. The clipboard itself is not cleared or altered. Diagnostics retain only success/failure, character count, representation, the managed-storage category and fixed redacted errors. They exclude note content, source application, filenames and URLs.

## Filenames and storage

The default is `Quick Note YYYY-MM-DD HH-mm.md`, with collision suffixes such as `Quick Note YYYY-MM-DD HH-mm 2.md`. A compact timestamp is also available.

Heading-based names are opt-in. Because even a short, syntactically safe heading can contain a password or private sentence, only generic headings such as Notes, Ideas, Checklist, Plan or Summary are eligible. Other headings, including headings inside code fences, fall back to the timestamp. This deliberately prioritizes privacy over descriptive automatic filenames. Rename is available through the normal file context menu.

Files live in the sandbox's Application Support directory under `Nodebay/Quick Notes`, not a temporary directory or Downloads. Settings' Show Notes Folder reveals it. Notes use private file permissions, an exclusively created temporary sibling, a synchronized write, and atomic no-overwrite hard-link promotion. Only the operation's own temporary sibling is removed after success, failure or cancellation.

Notes are regular `.md` files with the usual shelf bookmarks. They use the existing Space/Quick Look, native drag, context menu, stack and selection workflows. Removing a tile only removes its shelf reference; the note remains on disk and shelf removal supports the existing Undo action. Relaunch does not remove saved notes. If automatic shelf insertion is disabled, files are still saved in the same persistent folder.

## Verification

`python3 -m unittest discover -s tests -p 'test_*.py' -v` includes compiled Swift Quick Notes fixtures for exact content, Unicode, large input, routing, rich/plain fallback, collisions, permissions, bookmark restoration, injected partial-write failure and temporary cleanup. Existing shelf contract tests cover Quick Look, native drag, removal and Undo wiring. These contract checks are not proof of a physical Finder or other-app drag.

Physical UI, built-in/external display, signing and release status are recorded separately in the [Quick Notes verification report](../quick-notes-verification.md).
