# Markdown conversion

Compatible non-Markdown documents show **Convert to MD**. Existing `.md` and `.markdown` files never show the action. Each conversion runs outside the main UI through bundled, unmodified Microsoft MarkItDown 0.1.7 and writes an atomic, collision-safe Markdown copy beside the source before adding it to the shelf.

PDF and DOCX are covered by generated real fixtures. Unsupported, empty, scanned, encrypted, malformed, or permission-denied files produce recoverable errors. The source is never used as the output. Batch jobs limit concurrency, preserve successful outputs, and report skipped and failed members separately.
