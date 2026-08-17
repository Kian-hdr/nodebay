# External displays

Nodebay supports built-in only, selected display, main display, follow-pointer active display, and all-display modes. Displays without a physical notch receive a virtual top-center notch. Stable display identifiers preserve selection where macOS exposes them.

Window coordination handles screen changes and shared state without duplicating processing actions. Hot-plugging, mixed scaling, clamshell mode, rotation, Spaces, full-screen apps, Mission Control, and Stage Manager require hardware-specific manual regression checks before each release.
