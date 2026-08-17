cask "nodebay" do
  arch arm: "arm64"

  version "0.1.0"
  sha256 arm: "55ef257f293e77f680b75483c998e334d8061606203f6dc436a01038a5b63c29"

  url "https://github.com/Kian-hdr/nodebay/releases/download/nodebay-v#{version}/Nodebay-#{version}-#{arch}.zip"
  name "Nodebay"
  desc "Local-first utility bay for the MacBook notch and external displays"
  homepage "https://github.com/Kian-hdr/nodebay"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Nodebay.app"

  uninstall quit: "theboringteam.boringnotch"

  livecheck do
    url :url
    regex(/^nodebay-v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  zap trash: [
    "~/Library/Application Support/Nodebay",
    "~/Library/Caches/theboringteam.boringnotch",
    "~/Library/Preferences/theboringteam.boringnotch.plist",
  ]
end
