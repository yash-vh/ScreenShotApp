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

When preparing a new release, you can build, package, and publish directly to GitHub in a single command:

```bash
Scripts/package-release.sh 1.0.0 --publish
```

This single command automatically:
- Compiles `ScreenMint.app` with Release optimizations.
- Creates `release/ScreenMint-1.0.0.dmg`.
- Computes SHA256 checksum and updates `Casks/screenmint.rb`.
- Commits the updated Cask and creates the git tag `v1.0.0`.
- Pushes the tag to GitHub and creates the GitHub Release with the DMG attached.

If you only want to package locally without uploading, omit `--publish`:
```bash
Scripts/package-release.sh 1.0.0
```

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

