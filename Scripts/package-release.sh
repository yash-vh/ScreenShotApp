#!/bin/zsh
# Builds ScreenMint in Release configuration (if needed), packages it into a distributable DMG,
# computes the SHA256 checksum, updates Casks/screenmint.rb, and optionally publishes to GitHub.
#
# Usage:
#   Scripts/package-release.sh [version] [--publish] [path/to/ScreenMint.app]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plist="$repo_root/Sources/Resources/Info.plist"

publish=false
version=""
app_path=""

for arg in "$@"; do
  case "$arg" in
    --publish|-p)
      publish=true
      ;;
    *)
      if [[ -z "$version" ]]; then
        version="$arg"
      elif [[ -z "$app_path" ]]; then
        app_path="$arg"
      fi
      ;;
  esac
done

if [[ -z "$version" ]]; then
  version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "1.0.0")"
fi

# Detect GitHub repo slug (e.g. yash-vh/ScreenShotApp) from git remote
remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
repo_slug=$(echo "$remote_url" | sed -E 's/.*github\.com[:\/]([^\/]+\/[^\/\.]+)(\.git)?$/\1/' || echo "")
if [[ -z "$repo_slug" ]]; then
  repo_slug="yash-vh/ScreenShotApp"
fi

release_dir="$repo_root/release"
mkdir -p "$release_dir"

if [[ -z "$app_path" ]]; then
  candidate_build="$repo_root/build/DerivedData/Build/Products/Release/ScreenMint.app"
  echo "==> Building ScreenMint (Release configuration)..."
  xcodebuild -project "$repo_root/ScreenMint.xcodeproj" \
             -scheme ScreenMint \
             -configuration Release \
             -derivedDataPath "$repo_root/build/DerivedData" \
             -quiet \
             build
  app_path="$candidate_build"
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

  url "https://github.com/${repo_slug}/releases/download/v#{version}/ScreenMint-#{version}.dmg"
  name "ScreenMint"
  desc "Native macOS screenshot capture, annotation, and screen recording tool"
  homepage "https://github.com/${repo_slug}"

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

if [[ "$publish" == true ]]; then
  echo ""
  echo "==> Publishing release v$version directly to GitHub..."

  tag="v$version"

  # 1. Commit updated Casks/screenmint.rb if changed
  if ! git -C "$repo_root" diff --quiet "$cask_file"; then
    echo "==> Committing updated Casks/screenmint.rb..."
    git -C "$repo_root" add "$cask_file"
    git -C "$repo_root" commit -m "chore(release): bump cask to $version"
  fi

  # 2. Tag release
  if git -C "$repo_root" rev-parse "$tag" >/dev/null 2>&1; then
    echo "==> Tag $tag already exists locally."
  else
    echo "==> Creating git tag $tag..."
    git -C "$repo_root" tag -a "$tag" -m "Release $version"
  fi

  # 3. Push branch and tag
  current_branch=$(git -C "$repo_root" branch --show-current 2>/dev/null || echo "main")
  echo "==> Pushing $current_branch and $tag to origin..."
  git -C "$repo_root" push origin "$current_branch" || true
  git -C "$repo_root" push origin "$tag" || true

  # 4. Create or update GitHub Release with the DMG asset
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "==> Uploading release to GitHub via gh CLI..."
    if gh release view "$tag" >/dev/null 2>&1; then
      echo "==> Release $tag already exists on GitHub. Uploading $dmg_name..."
      gh release upload "$tag" "$dmg_path" "$sha_path" --clobber
    else
      echo "==> Creating new release $tag on GitHub with $dmg_name..."
      gh release create "$tag" "$dmg_path" "$sha_path" \
        --title "ScreenMint $version" \
        --notes "ScreenMint $version release. Download ScreenMint-${version}.dmg below or install using Homebrew."
    fi

    release_url=$(gh release view "$tag" --json url -q .url 2>/dev/null || echo "https://github.com/${repo_slug}/releases/tag/$tag")
    echo ""
    echo "=================================================="
    echo "🎉 Release published to GitHub successfully!"
    echo "Release URL: $release_url"
    echo ""
    echo "Users can install via Homebrew with:"
    echo "  brew install --cask https://raw.githubusercontent.com/${repo_slug}/main/Casks/screenmint.rb"
    echo "=================================================="
  else
    echo ""
    echo "Warning: 'gh' CLI is not authenticated or not installed." >&2
    echo "Please upload $dmg_path manually to:" >&2
    echo "  https://github.com/${repo_slug}/releases/new?tag=$tag" >&2
  fi
else
  echo ""
  echo "💡 Tip: To automatically tag, push, and publish to GitHub Releases in one step, run:"
  echo "  ./Scripts/package-release.sh $version --publish"
fi

