cask "nodebay" do
  version "1.2.0"
  sha256 "7acb9b1b966cafe38158d1044088e411d4703a25a38c6041016a5b7f6c719f12"

  url "https://github.com/Kian-hdr/nodebay/releases/download/nodebay-v#{version}/Nodebay-#{version}-arm64.dmg"
  name "Nodebay"
  desc "Local-first utility bay for the MacBook notch and external displays"
  homepage "https://github.com/Kian-hdr/nodebay"

  livecheck do
    url :url
    regex(/^nodebay-v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on formula: "yt-dlp"
  depends_on formula: "ffmpeg"

  app "Nodebay.app"

  uninstall quit: "theboringteam.boringnotch"

  zap trash: [
    "~/Library/Caches/theboringteam.boringnotch",
    "~/Library/Preferences/theboringteam.boringnotch.plist",
  ]
end
