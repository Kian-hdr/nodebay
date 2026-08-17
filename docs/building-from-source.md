# Building from source

Requirements: Apple Silicon, macOS 15 or later, Xcode 26 or later, Homebrew, and the pinned Homebrew Python 3.13 runtime.

```bash
git clone https://github.com/Kian-hdr/nodebay.git
cd nodebay
git switch dev
brew install python@3.13 yt-dlp ffmpeg
./scripts/build_markitdown_runtime.sh
./scripts/test_markitdown_runtime.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

The scheme and selected internal symbols retain historical names to protect preference, Accessibility, XPC, bookmark, and saved-state migration. Generated Python runtimes and Xcode build output are ignored and must not be committed.
