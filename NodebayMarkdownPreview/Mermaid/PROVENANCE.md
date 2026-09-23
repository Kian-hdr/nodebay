# Bundled Mermaid

- Package: `mermaid` version **12.0.0**, pinned, MIT license (see `LICENSE`).
- Official usage/API documentation: https://mermaid.js.org/config/usage.html
- Official package metadata: https://registry.npmjs.org/mermaid/12.0.0
- Archive: https://registry.npmjs.org/mermaid/-/mermaid-12.0.0.tgz
- Retrieved: 2026-09-12.
- Archive integrity verified against npm metadata: `sha512-/wQXC9iBxoGV8p3erbvaXs9h77VyLDBH6GdayVjj3hEcSQhFU4N1WUhUppotCEqlIxI2pRMwjwBSwTB1MfZBgQ==`.
- Unmodified `dist/mermaid.min.js` SHA-256: `28fca7ae6ebc7ed7bb63bde63136a74bfef14f296a57e403657eeb8b32836073`.
- The bundle contains Mermaid's bundled dependencies and their embedded license notices; keep those notices intact.
- `renderer.html` and `renderer.js` are Nodebay integration code, not upstream Mermaid code.

The distribution is entirely local. No CDN, font download, remote image or plugin
is loaded. macOS requires the network-client sandbox entitlement to start WebKit
even for local files; CSP, content rules and navigation restrictions block remote
resources in this renderer. Configuration directives/frontmatter and
embedded HTML/image resources are unsupported in previews and preserve the
original Mermaid code block through the caller's fallback. The renderer uses
Dagre layout, disables HTML labels and interactions, and produces a static PNG.
