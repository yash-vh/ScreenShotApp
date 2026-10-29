# Homebrew Distribution Guide for ScreenMint

This document outlines how to distribute **ScreenMint** via Homebrew Cask and how users can install it using `brew`.

---

## 1. How Users Install ScreenMint via Brew

### Method A: Direct URL Cask Install (No Tap Required)
Any macOS user with Homebrew installed can run:
```bash
brew install --cask https://raw.githubusercontent.com/yash-vh/ScreenShotApp/main/Casks/screenmint.rb
```

### Method B: Tapping this Repository
Users can tap this repository directly and install:
```bash
brew tap yash-vh/screenmint https://github.com/yash-vh/ScreenShotApp
brew install --cask screenmint
```

### Method C: Dedicated Tap (`brew tap yash-vh/screenmint`)
By setting up a GitHub repository named `homebrew-screenmint` (see Step 3 below), users can simply run the standard two-line brew command:
```bash
brew tap yash-vh/screenmint
brew install --cask screenmint
```
or single-line:
```bash
brew install --cask yash-vh/screenmint/screenmint
```

---

## 2. Packaging Releases for Homebrew

When preparing a new release:

1. Build and package the release DMG:
   ```bash
   Scripts/package-release.sh 1.0.0
   ```
   This automatically:
   - Compiles `ScreenMint.app` with Release optimizations.
   - Creates `release/ScreenMint-1.0.0.dmg`.
   - Computes SHA256 checksum into `release/ScreenMint-1.0.0.dmg.sha256`.
   - Updates `Casks/screenmint.rb` with the new version and checksum.

2. Create a GitHub Release:
   - Tag the release: `git tag v1.0.0 && git push origin v1.0.0`
   - Create a Release for `v1.0.0` on GitHub:
     `https://github.com/yash-vh/ScreenShotApp/releases/new`
   - Upload `release/ScreenMint-1.0.0.dmg` and `release/ScreenMint-1.0.0.dmg.sha256` to the release assets.
   - Publish the release.

---

## 3. Setting Up a Dedicated Tap (Optional but Recommended)

Homebrew's convention for personal taps is a repository starting with `homebrew-`:

1. On GitHub, create a new public repository named **`homebrew-screenmint`** under your account (`yash-vh/homebrew-screenmint`).
2. Clone it and create the `Casks/` directory:
   ```bash
   git clone https://github.com/yash-vh/homebrew-screenmint.git
   cd homebrew-screenmint
   mkdir Casks
   cp /path/to/ScreenShotApp/Casks/screenmint.rb Casks/screenmint.rb
   git add Casks/screenmint.rb
   git commit -m "Add screenmint cask v1.0.0"
   git push origin main
   ```
3. Now any user on macOS can install with:
   ```bash
   brew tap yash-vh/screenmint
   brew install --cask screenmint
   ```

---

## 4. Submitting to Official Homebrew (`homebrew/cask`)

Once ScreenMint has a public release on GitHub, you can submit it to the official Homebrew Cask repository:

```bash
brew tap homebrew/cask
brew create --cask https://github.com/yash-vh/ScreenShotApp/releases/download/v1.0.0/ScreenMint-1.0.0.dmg
```

Once accepted into `homebrew/cask`, users worldwide can install with simply:
```bash
brew install --cask screenmint
```

