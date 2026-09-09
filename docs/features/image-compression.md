# Image compression

Supported images show **Compress Image** when `/Applications/ImageOptim.app` is detected. Nodebay creates a collision-safe copy in its persistent Application Support `Nodebay/Generated Images` directory, invokes ImageOptim only on the copy, validates the result, and adds it beside the source shelf reference. The original image and its folder are left unchanged. File access stays active until the copy is made, so compression does not require permission to write beside the original, including images in read-only or file-provider folders. Drag the result from the shelf to export it.

The result reports original size, output size, bytes and percentage saved, and the selected metadata and lossless or lossy settings where known. If no useful reduction occurs, the user can keep or discard the generated copy. Automatic compression is disabled by default.
