# Proposed video-to-GIF conversion

Status: initial bounded implementation added on 2026-08-29. The first version automatically converts complete MP4, MOV, and M4V videos up to 15 seconds at 12 fps. Longer videos remain in their original playable format. Advanced trim, size, loop, and poster controls remain proposed work.

## User need

Convert a short local video, such as an MP4 simulation capture, into a presentation-ready animated GIF directly from the Nodebay shelf. The immediate use case is preparing silent loops for a native Google Slides pitch deck while preserving a separate PDF-safe poster frame.

## Why it belongs in Nodebay

Nodebay already treats the shelf as a local file-processing surface and already detects a separately installed FFmpeg engine. A bounded video-to-GIF action extends that model without introducing a cloud service or changing the original file.

## Proposed interaction

1. Drop or retain a supported local video on the shelf.
2. Choose **Video Actions > Create GIF**.
3. Nodebay reads the complete video duration automatically.
4. Videos up to 15 seconds are converted at 12 fps and fit within 960 × 540 while preserving aspect ratio.
5. Longer videos are kept as videos and can be opened directly from the fallback notice.
6. Nodebay writes a collision-safe persistent GIF in its managed storage and places it beside the source item on the shelf.

The original video must never be overwritten, moved, or modified.

## Presentation preset

Default **Pitch GIF** preset:

- duration: 5 seconds;
- output: 960 × 540 or fit within that box while preserving aspect ratio;
- frame rate: 12 fps;
- loop: continuous;
- palette: generated from the selected clip;
- target size: 8 MB or less where feasible;
- companion output: optional PNG poster frame.

Additional compact presets may use 480p at 8 or 10 fps. A 720p preset should warn that detailed or photographic footage can become large and that MP4 is normally more efficient.

## Technical approach

Use the locally detected FFmpeg executable through Nodebay's existing approved-engine and XPC execution path. Generate a palette from the selected clip, then apply that palette during GIF encoding. Do not invoke a shell, send media over the network, or require a new cloud account.

The implemented conversion is bounded by:

- a 15-second maximum duration and 180-frame maximum;
- validated numeric ranges for width and frame rate;
- a job timeout and cancellation;
- bounded diagnostic output;
- collision-safe output naming;
- post-conversion validation that the output exists, is a GIF, contains more than one frame, and is non-empty;
- automatic fallback to the unchanged original video when its duration exceeds the GIF limit.

## Suggested first scope

Supported input types: MP4, MOV, and M4V files that the installed FFmpeg build can decode.

Controls:

- trim start and duration;
- 480p, 540p, and 720p size presets;
- 8, 10, 12, and 15 fps;
- continuous loop or play once;
- fit, fill, or original aspect behavior;
- optional poster-frame PNG.

Out of scope for the first version:

- video editing or timeline composition;
- audio preservation, because GIF has no audio;
- downloading source media;
- cloud conversion;
- claiming an exact output size before encoding;
- animated PDF authoring.

## Acceptance criteria

- A real MP4 fixture converts into a readable multi-frame GIF.
- The original MP4 hash remains unchanged.
- The output name is collision-safe and the result appears on the shelf.
- Trim, scaling, frame-rate, and loop settings match the selected values.
- Cancel, timeout, missing FFmpeg, unsupported input, decode failure, permission denial, and oversized result are recoverable and clearly reported.
- The generated GIF opens in Quick Look and plays after direct insertion into a native Google Slides test deck.
- The optional poster frame remains meaningful after placement in an exported PDF.

## Important delivery constraint

This feature would prepare assets for native presentation files. It cannot make an animated GIF remain animated after ordinary PDF export. The PDF workflow must use the poster frame, filmstrip, or consecutive static slides instead.
