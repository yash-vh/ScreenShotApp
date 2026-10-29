#!/bin/zsh
# Generates the launcher icon (AppIcon.appiconset), in-app logo (AppLogo.imageset),
# and menu bar icon (MenuBarIcon.imageset) from source branding assets.
#
# Usage:
#   Scripts/generate-app-icon.sh [path/to/logo.png] [path/to/menubar.png]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_logo="${1:-$repo_root/Branding/ScreenMint-logo.png}"
source_menubar="${2:-$repo_root/Branding/ScreenMint-menubar.png}"

if [[ ! -f "$source_logo" || ! -f "$source_menubar" ]]; then
  echo "Generating fresh branding assets using Scripts/make-logo.swift..."
  swiftc -module-cache-path /tmp/ModuleCache "$repo_root/Scripts/make-logo.swift" -o /tmp/screenmint-make-logo
  /tmp/screenmint-make-logo all
fi

[[ -f "$source_logo" ]] || { echo "Error: source logo not found at $source_logo" >&2; exit 1; }

assets="$repo_root/Sources/Resources/Assets.xcassets"
icon_set="$assets/AppIcon.appiconset"
logo_set="$assets/AppLogo.imageset"
menubar_set="$assets/MenuBarIcon.imageset"

mkdir -p "$icon_set" "$logo_set" "$menubar_set"

render() { # size src dst
  sips -s format png -z "$1" "$1" "$2" --out "$3" >/dev/null
}

echo "Generating launcher icon set (AppIcon)..."
images=()
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    name="icon_${size}x${size}@${scale}x.png"
    render $(( size * scale )) "$source_logo" "$icon_set/$name"
    images+=("    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${size}x${size}\" }")
  done
done
{
  echo '{'
  echo '  "images" : ['
  print -l -- ${(j:,\n:)images}
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} > "$icon_set/Contents.json"

echo "Generating in-app logo image set (AppLogo)..."
logo_images=()
for scale in 1 2 3; do
  name="logo@${scale}x.png"
  render $(( 64 * scale )) "$source_logo" "$logo_set/$name"
  logo_images+=("    { \"filename\" : \"$name\", \"idiom\" : \"universal\", \"scale\" : \"${scale}x\" }")
done
{
  echo '{'
  echo '  "images" : ['
  print -l -- ${(j:,\n:)logo_images}
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} > "$logo_set/Contents.json"

if [[ -f "$source_menubar" ]]; then
  echo "Generating menu bar template icon set (MenuBarIcon)..."
  render 18 "$source_menubar" "$menubar_set/menubar.png"
  render 36 "$source_menubar" "$menubar_set/menubar@2x.png"
  cat << 'EOF' > "$menubar_set/Contents.json"
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
EOF
fi

echo "Successfully updated assets in $assets"
