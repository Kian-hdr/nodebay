# ImageOptim

- Purpose: local image compression through a safe copy
- Version: detected and tested at 1.9.3; not bundled
- Status: separately installed companion at `/Applications/ImageOptim.app`
- Behavior: local-only; Nodebay does not use the ImageOptim cloud API
- Inputs: image types supported by the installed ImageOptim release
- Output: collision-safe optimized copy
- Permissions: read access to the generated copy and its result location
- Failure: original hash remains unchanged; error is recoverable; generated copy is cleaned or offered according to job state
- Diagnostics: installation, version, exit status, size comparison, and bounded errors
- Source: https://imageoptim.com/mac
- License: GPL-2.0-or-later; Nodebay does not bundle ImageOptim

ImageOptim does not endorse Nodebay.
