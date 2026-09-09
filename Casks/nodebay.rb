cask "nodebay" do
  version "1.2.1"
  sha256 "36dfbedca999208f4808ff10f3f0767743f0b186c82eacf0b3494a4bcec47565"

  url "https://github.com/Kian-hdr/nodebay/releases/download/nodebay-v#{version}/Nodebay-#{version}-arm64.dmg"
  name "Nodebay"
  desc "Local-first utility bay for the MacBook notch and external displays"
  homepage "https://github.com/Kian-hdr/nodebay"

  livecheck do
    url :url
    regex(/^nodebay-v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  auto_updates true
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
