# Contributing to Nodebay

Nodebay welcomes focused code, documentation, accessibility, design, and testing contributions. Open an issue before starting a large behavioral or architectural change.

## Development flow

1. Fork and clone `https://github.com/Kian-hdr/nodebay`.
2. Branch from `dev` for application changes.
3. Keep original user files immutable in every shelf or processing workflow.
4. Add or update tests for behavior, licensing, privacy, and packaging changes.
5. Run the checks below.
6. Open a pull request into `dev` with screenshots for visible changes.

```bash
python3 -m unittest discover -s Tests -p 'test_*.py' -v
python3 scripts/generate_nodebay_notices.py --check
zsh -n scripts/*.sh
xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

The Xcode scheme and some internal `BoringNotch` symbols remain temporarily for migration compatibility. Do not rename internal identifiers without a tested state, permission, login-item, bookmark, and XPC migration.

## Safety requirements

- Never overwrite, modify, move, or delete an original user file.
- Treat shelf removal as reference removal and preserve Undo.
- Use collision-safe names for outputs.
- Use structured `Process` arguments. Never interpolate user input into a shell command.
- Keep document and image processing local.
- Do not add analytics, a proxy, or a Nodebay cloud dependency.
- Do not log document contents, cookies, private URLs, or sensitive filenames.
- Do not bundle an engine without a pinned version, source URL, license, notice, and corresponding-source review.

## Reports and fixtures

Use public-domain, generated, or locally hosted fixtures. Never attach private documents, cookies, downloaded copyrighted media, personal filenames, or unsanitized logs to a public issue or pull request.

Nodebay is based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch). Contributions must preserve its copyright notices, GPL-3.0 terms, and the notices for every third-party component.
