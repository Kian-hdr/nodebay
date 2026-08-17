# Nodebay security policy

## Reporting a vulnerability

Do not open a public issue for a vulnerability. Use the private **Report a vulnerability** form in this repository's Security tab:

`https://github.com/Kian-hdr/nodebay/security/advisories/new`

Include the affected Nodebay version, macOS version, architecture, impact, reproduction steps, and the smallest safe proof of concept. Do not submit private documents, browser cookies, credentials, downloaded media, personal filenames, or unsanitized processing logs.

Security-sensitive areas include file promises, security-scoped bookmarks, XPC engine isolation, downloader path handling, browser integration, update signing, notarization, and third-party runtime packaging.

Vulnerabilities in an unmodified companion or engine should also be reported to that project's maintainers. Do not publicly disclose a Nodebay-specific exploit before a coordinated fix is available.

## Supported versions

Until the first public Nodebay release is published, only the current `dev` branch receives security fixes. This section will be updated with supported release lines after publication.
