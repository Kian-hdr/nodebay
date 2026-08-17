# Nodebay release checklist

- [ ] Release commit and tag are identified
- [ ] Working tree is clean and generated artifacts are excluded
- [ ] Debug and Release builds pass on Apple Silicon
- [ ] Automated tests and license-notice validation pass
- [ ] PDF and DOCX conversion fixtures pass without changing sources
- [ ] Downloader and ImageOptim copy-first fixtures pass
- [ ] UI, accessibility, stacks, Finder dragging, and external displays are manually checked
- [ ] Developer ID signature, hardened runtime, and release entitlements pass
- [ ] Archive is notarized and the ticket is stapled
- [ ] Gatekeeper accepts the stapled app
- [ ] Source, notices, dependency manifest, privacy statement, and checksums are included
- [ ] Homebrew cask syntax, audit, install, launch, and uninstall checks pass
- [ ] README screenshots and release notes match tested functionality
- [ ] One final approval covers the exact tag, assets, release text, and external destinations
- [ ] No credentials, cookies, private paths, signing material, build caches, or generated runtimes are committed

