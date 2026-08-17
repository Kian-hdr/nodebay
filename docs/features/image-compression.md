# Image compression

Supported images show **Compress Image** when `/Applications/ImageOptim.app` is detected. Nodebay creates a collision-safe copy, records the source hash, invokes ImageOptim only on the copy, validates the result, and adds it beside the source shelf reference.

The result reports original size, output size, bytes and percentage saved, and the selected metadata and lossless or lossy settings where known. If no useful reduction occurs, the user can keep or discard the generated copy. Automatic compression is disabled by default.
