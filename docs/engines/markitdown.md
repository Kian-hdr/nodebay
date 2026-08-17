# Microsoft MarkItDown

- Purpose: local document-to-Markdown conversion
- Version: bundled and pinned at 0.1.7
- Status: unmodified generated runtime inside `Nodebay.app/Contents/Resources/markitdown-runtime`
- Behavior: local-only; socket creation is denied and proxy variables are removed
- Inputs: PDF, DOCX, PPTX, XLSX, XLS, HTML, CSV, JSON, XML, EPUB, MSG, ZIP, and explicit text formats
- Output: separate UTF-8 Markdown file
- Permissions: read access to the source and write access to the output directory
- Failure: bounded error, no source mutation, partial batch successes retained
- Diagnostics: version and health check only; routine logs exclude document content
- Source: https://github.com/microsoft/markitdown
- License: MIT; full runtime notices in `THIRD_PARTY_LICENSES_MARKITDOWN`

Microsoft does not endorse or sponsor Nodebay.
