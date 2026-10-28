#!/bin/zsh
# Generates the launcher icon (AppIcon.appiconset) and in-app logo (AppLogo.imageset) from one source logo.
# Usage: Scripts/generate-app-icon.sh path/to/logo.png   (square PNG, 1024×1024 recommended)
set -euo pipefail

source_logo=${1:?"Usage: $0 path/to/logo.png"}
[[ -f $source_logo ]] || { echo "No such file: $source_logo" >&2; exit 1; }

assets="$(cd "$(dirname "$0")/.." && pwd)/Sources/Resources/Assets.xcassets"
icon_set="$assets/AppIcon.appiconset"
logo_set="$assets/AppLogo.imageset"

render() { # size output
  sips -s format png -z "$1" "$1" "$source_logo" --out "$2" >/dev/null
}

# Launcher icon: every macOS size at 1x and 2x
images=()
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    name="icon_${size}x${size}@${scale}x.png"
    render $(( size * scale )) "$icon_set/$name"
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

# In-app logo (menu header, About): 64pt base
logo_images=()
for scale in 1 2 3; do
  name="logo@${scale}x.png"
  render $(( 64 * scale )) "$logo_set/$name"
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

echo "Updated $icon_set and $logo_set from $source_logo"
