cask "screenmint" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/yash-vh/ScreenShotApp/releases/download/v#{version}/ScreenMint-#{version}.dmg"
  name "ScreenMint"
  desc "Native macOS screenshot capture, annotation, and screen recording tool"
  homepage "https://github.com/yash-vh/ScreenShotApp"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "ScreenMint.app"

  uninstall quit: "com.screenshotapp.mac"

  zap trash: [
    "~/Library/Application Support/com.screenshotapp.mac",
    "~/Library/Caches/com.screenshotapp.mac",
    "~/Library/HTTPStorages/com.screenshotapp.mac",
    "~/Library/LaunchAgents/com.screenshotapp.mac.relauncher.plist",
    "~/Library/Preferences/com.screenshotapp.mac.plist",
    "~/Library/Saved Application State/com.screenshotapp.mac.savedState",
  ]
end

