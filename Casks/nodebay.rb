cask "nodebay" do
  arch arm: "arm64"

  version "0.1.0"
  sha256 arm: "e31f65f6e271528b25072d3afa5d6c90340ddefa49083158cdde028b96f0dec2"

  url "https://github.com/Kian-hdr/boring.notch/releases/download/nodebay-v#{version}/Nodebay-#{version}-#{arch}.zip"
  name "Nodebay"
  desc "Local-first utility bay for the MacBook notch and external displays"
  homepage "https://github.com/Kian-hdr/boring.notch"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Nodebay.app"

  zap trash: [
    "~/Library/Application Support/Nodebay",
    "~/Library/Caches/theboringteam.boringnotch",
    "~/Library/Preferences/theboringteam.boringnotch.plist",
  ]
end
