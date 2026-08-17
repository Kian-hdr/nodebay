cask "nodebay" do
  version "0.1.1"
  sha256 "c497711aebcc549666f5f607e1c6c789d70c28d2636352ed918409f7197fb2a7"

  url "https://github.com/Kian-hdr/nodebay/releases/download/nodebay-v#{version}/Nodebay-#{version}-arm64.zip"
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

  app "Nodebay.app"

  uninstall quit: "theboringteam.boringnotch"

  zap trash: [
    "~/Library/Application Support/Nodebay",
    "~/Library/Caches/theboringteam.boringnotch",
    "~/Library/Preferences/theboringteam.boringnotch.plist",
  ]
end
