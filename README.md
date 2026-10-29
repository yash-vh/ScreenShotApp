# ScreenMint 🍃📸

**ScreenMint** is a powerful, lightweight, native macOS screenshot capture, annotation, and screen recording tool built with SwiftUI and AppKit. It lives quietly in your menu bar, ready to capture regions, entire windows, full displays, and extract OCR text in a heartbeat.

---

## 🚀 Installation

### Option 1: Install with Homebrew (Recommended)

You can download and install ScreenMint directly using `brew`:

#### Direct Cask Install
```bash
brew install --cask https://raw.githubusercontent.com/yash-vh/ScreenShotApp/main/Casks/screenmint.rb
```

#### Via GitHub Tap
Tap this repository and install the cask:
```bash
brew tap yash-vh/screenshotapp https://github.com/yash-vh/ScreenShotApp
brew install --cask screenmint
```

*(If you set up a dedicated `homebrew-screenmint` tap on GitHub, users can also install with:)*
```bash
brew tap yash-vh/screenmint
brew install --cask screenmint
```

To upgrade in the future:
```bash
brew upgrade --cask screenmint
```

---

### Option 2: Download DMG from GitHub Releases

1. Download the latest `ScreenMint-1.0.0.dmg` from [Releases](https://github.com/yash-vh/ScreenShotApp/releases).
2. Open `ScreenMint-1.0.0.dmg`.
3. Drag **ScreenMint.app** into your **Applications** folder.

---

## ✨ Features

- **Instant Region & Window Capture:** Drag to snap any region or click to capture any open window.
- **Full Display & Multi-Display Support:** Capture current display or stitch multi-monitor setups.
- **Live Annotation Suite:**
  - Rectangles, rounded boxes, circles, and freehand pen drawing.
  - Directional arrows and precision lines.
  - Numbered step badges that automatically increment.
  - Text callouts and highlighters.
  - Sensitive data blurring and redaction (passwords, emails, keys).
- **OCR Text Recognition:** Extract text directly from any captured area onto your clipboard using Apple Vision.
- **Screen Recording with Audio:** Record full screen, window, or cropped regions with optional microphone commentary.
- **Spotlight Indexing:** Search your past captures directly from macOS Spotlight by text, title, or tags.
- **Cloud & Local Storage:**
  - Save locally to Custom Folders, Desktop, Documents, or Downloads.
  - Optional one-click uploads to ImgBB or custom Amazon S3 / S3-compatible buckets.
- **Native macOS Design:** macOS Sonoma & Sequoia continuous squircle aesthetics, responsive dark/light menu bar icon, and minimal system footprint.

---

## 🛠️ Building from Source

### Prerequisites

- **macOS:** 14.0+ (Sonoma or Sequoia)
- **Xcode:** 15.0+
- **XcodeGen:** (`brew install xcodegen`)

### Build Steps

1. Clone repository:
   ```bash
   git clone https://github.com/yash-vh/ScreenShotApp.git
   cd ScreenShotApp
   ```

2. Generate Xcode project:
   ```bash
   xcodegen generate
   ```

3. Build Debug or Release:
   ```bash
   # Debug Build
   xcodebuild -project ScreenshotApp.xcodeproj -scheme ScreenshotApp build

   # Release Build
   xcodebuild -project ScreenshotApp.xcodeproj -scheme ScreenshotApp -configuration Release build
   ```

4. Run Unit Tests:
   ```bash
   xcodebuild test -project ScreenshotApp.xcodeproj -scheme ScreenshotApp -destination 'platform=macOS'
   ```

---

## 🎨 Branding & Assets

ScreenMint includes automated graphic generation scripts:

- **Generate App Icon & Menu Bar Glyph:**
  ```bash
  swift Scripts/make-logo.swift all
  ```
- **Update Asset Catalogs (`AppIcon`, `AppLogo`, `MenuBarIcon`):**
  ```bash
  Scripts/generate-app-icon.sh
  ```
- **Build Release DMG & Update Homebrew Cask:**
  ```bash
  Scripts/package-release.sh [version]
  ```

---

## 📄 License

Copyright © 2026 Yash Nandha. All rights reserved.

