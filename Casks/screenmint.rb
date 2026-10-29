cask "screenmint" do
  version "1.0.0"
  sha256 "3735ea5da733eb209092f9411e8da4b7915cc79ee21bcd0d2a2456b5db05426a"

  url "https://github.com/yash-vh/ScreenShotApp/releases/download/v#{version}/ScreenMint-#{version}.dmg"
  name "ScreenMint"
  desc "Native macOS screenshot capture, annotation, and screen recording tool"
  homepage "https://github.com/yash-vh/ScreenShotApp"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "ScreenMint.app"

  uninstall quit: "com.screenmint.mac"

  zap trash: [
    "~/Library/Application Support/com.screenmint.mac",
    "~/Library/Caches/com.screenmint.mac",
    "~/Library/HTTPStorages/com.screenmint.mac",
    "~/Library/LaunchAgents/com.screenmint.mac.relauncher.plist",
    "~/Library/Preferences/com.screenmint.mac.plist",
    "~/Library/Saved Application State/com.screenmint.mac.savedState",
  ]
end
