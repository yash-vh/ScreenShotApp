# Build and Test Instructions

## Prerequisites

- **macOS:** 14.0+ (Sonoma or Sequoia)
- **Xcode:** 15.0+ or Command Line Tools
- **XcodeGen:** Installed via Homebrew (`brew install xcodegen`)

---

## 1. Project Generation

To generate or regenerate the Xcode project from `project.yml`:

```bash
xcodegen generate
```

This creates `ScreenshotApp.xcodeproj` with configured targets:
- `ScreenshotApp` (macOS Native Application)
- `ScreenshotAppTests` (XCTest Suite)

---

## 2. Building from Command Line

### Debug Build
```bash
xcodebuild -project ScreenshotApp.xcodeproj \
           -scheme ScreenshotApp \
           -destination 'platform=macOS' \
           build \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO
```

### Release Build
```bash
xcodebuild -project ScreenshotApp.xcodeproj \
           -scheme ScreenshotApp \
           -configuration Release \
           -destination 'platform=macOS' \
           build
```

---

## 3. Running Unit Tests

```bash
xcodebuild test \
           -project ScreenshotApp.xcodeproj \
           -scheme ScreenshotApp \
           -destination 'platform=macOS' \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO
```

---

## 4. Opening in Xcode

You can open the project directly:
```bash
open ScreenshotApp.xcodeproj
```
Select the **ScreenshotApp** scheme and press `Cmd + R` to run.
