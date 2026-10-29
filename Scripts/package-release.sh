#!/bin/zsh
# Builds ScreenMint in Release configuration (if needed), packages it into a distributable DMG,
# computes the SHA256 checksum, and updates Casks/screenmint.rb.
#
# Usage:
#   Scripts/package-release.sh [version] [path/to/ScreenMint.app]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plist="$repo_root/Sources/Resources/Info.plist"

version="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "1.0.0")}"
app_path="${2:-}"

release_dir="$repo_root/release"
mkdir -p "$release_dir"

if [[ -z "$app_path" ]]; then
  # Look for existing build or build it
  candidate_build="$repo_root/build/DerivedData/Build/Products/Release/ScreenMint.app"
  candidate_alt="/tmp/DerivedData/Build/Products/Release/ScreenMint.app"
  
  if [[ -d "$candidate_build" ]]; then
    app_path="$candidate_build"
  elif [[ -d "$candidate_alt" ]]; then
    app_path="$candidate_alt"
  else
    echo "==> Building ScreenMint (Release configuration)..."
    xcodebuild -project "$repo_root/ScreenMint.xcodeproj" \
               -scheme ScreenMint \
               -configuration Release \
               -derivedDataPath "$repo_root/build/DerivedData" \
               -quiet \
               build
    app_path="$candidate_build"
  fi
fi

if [[ ! -d "$app_path" ]]; then
  echo "Error: ScreenMint.app not found at $app_path" >&2
  exit 1
fi

echo "==> Packaging ScreenMint.app from $app_path..."
dmg_name="ScreenMint-${version}.dmg"
dmg_path="$release_dir/$dmg_name"
sha_path="$release_dir/$dmg_name.sha256"

work_dir=$(mktemp -d /tmp/screenmint-dmg.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

# Installer window: custom background with an arrow, app icon -> Applications, volume icon.
# dmgbuild writes Finder's layout directly (no Finder scripting); it lives in a private venv.
venv="$repo_root/build/.dmgbuild-venv"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
  echo "==> Installing dmgbuild into $venv..."
  python3 -m venv "$venv"
  "$venv/bin/pip" install -q dmgbuild
fi

echo "==> Drawing installer background..."
swift "$repo_root/Scripts/make-dmg-background.swift" "$work_dir/background.tiff"

echo "==> Creating disk image: $dmg_path"
rm -f "$dmg_path"
"$venv/bin/dmgbuild" -s "$repo_root/Scripts/dmg-settings.py" \
  -D app="$app_path" \
  -D background="$work_dir/background.tiff" \
  -D icon="$app_path/Contents/Resources/AppIcon.icns" \
  "ScreenMint" "$dmg_path" >/dev/null

echo "==> Calculating SHA256 checksum..."
sha=$(shasum -a 256 "$dmg_path" | awk '{print $1}')
echo "$sha  $dmg_name" > "$sha_path"

echo "==> Updating Casks/screenmint.rb with version $version and sha256 $sha..."
cask_file="$repo_root/Casks/screenmint.rb"
cat << EOF > "$cask_file"
cask "screenmint" do
  version "$version"
  sha256 "$sha"

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
EOF

echo ""
echo "=================================================="
echo "Release artifacts successfully created:"
echo "  DMG:     $dmg_path"
echo "  SHA256:  $sha"
echo "  Cask:    $cask_file"
echo "=================================================="

