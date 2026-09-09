# MediaRemoteAdapter source and build

Nodebay vendors a framework and helper built from unmodified upstream **v0.7.7**
sources, plus the matching Perl wrapper
from [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter/tree/e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6),
exact commit `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`.
The BSD-3-Clause license is included in [LICENSE](LICENSE), and its full text also
remains in Nodebay's `THIRD_PARTY_LICENSES`.

The framework and diagnostic helper were rebuilt with Apple's Xcode toolchain:

```sh
git clone https://github.com/ungive/mediaremote-adapter.git
cd mediaremote-adapter
git checkout --detach e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake --build build --parallel 2
```

Both binaries contain arm64 and x86_64 slices. Nodebay remains an Apple Silicon
product. The arm64 slices require macOS 15.0 and link only system libraries and
frameworks. Upstream still sets its internal framework version to `0.1.0`; the
source commit above, not that metadata field, identifies this vendored revision.
Public release packaging re-signs nested code with Nodebay's Developer ID.

The initial vendored build SHA-256 values, before release re-signing, are:

| File | SHA-256 |
|---|---|
| Framework executable | `0296903d9f4217e1440bf7c6bf96e37a07bb37942fdb6188e4b968d29890f950` |
| Diagnostic test client | `ebd4ba81b92127db4d3ff3e3af269a0280ae1ff1610030a68d02e4a1765cf6cf` |
| Perl wrapper | `d97802e46db9535e2549e178c105ebf417a0254b3929fc32f08ecfd14d49a85f` |

Nodebay opts into `stream --no-diff --allow-missing-title`. The last option fixes
untagged media such as audio shared in a chat app: a real Now Playing client can
publish playback state without a track title. Empty or incomplete client data is
still rejected. Nodebay labels an available untitled session without inventing
track metadata, and does not run the synthetic diagnostic player on startup.

`tests/MediaRemoteMetadataHarness.m` links the actual bundled framework to verify
its title-less-client and empty-client policy without publishing synthetic media.
`tests/NowPlayingStateHarness.swift` verifies source identity, untitled pause
retention, and clear-state behavior. These checks do not establish runtime
compatibility with every player or replace a recipient Mac's required permissions.
