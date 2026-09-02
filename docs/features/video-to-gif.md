# Video-to-GIF conversion

Nodebay 1.0.0 can create a presentation-friendly GIF from a local MP4, MOV, or M4V file through **Video Actions > Create GIF**.

- Videos up to 15 seconds are converted at 12 frames per second and fitted within 960 × 540 without changing the aspect ratio.
- Longer videos remain unchanged and Nodebay explains that they exceed the bounded GIF limit.
- FFmpeg runs locally through Nodebay's approved XPC process path with structured arguments, bounded diagnostics, and a two-minute timeout.
- The source video is copied to job-owned staging storage and is never overwritten, moved, or deleted.
- The GIF is validated as a multi-frame image, stored under Nodebay's Application Support directory, and added beside the source as a persistent draggable file.
- Output paths are collision-safe. A failed conversion removes only Nodebay-owned temporary and incomplete output data.

FFmpeg must be installed separately. Nodebay does not bundle, modify, or operate a cloud service for FFmpeg.
