# 1-Month Production Delivery & Milestone Plan

**Project:** ScreenshotApp (macOS Native Utility)  
**Target Delivery Window:** 4 Weeks (30 Days)  
**Deployment Target:** macOS 14.0+ (Sonoma, Sequoia)  
**Distribution:** Direct Website Download (Signed, Notarized DMG)  

---

## 1. Executive Roadmap (4-Week Schedule)

```
[ Week 1 ] ──▶ Foundation & Core Shell (M1) + Screen Capture Engine (M2)
[ Week 2 ] ──▶ Layered Annotation Editor (M3) + Styling & On-Device Recognition (M4)
[ Week 3 ] ──▶ Local History & SwiftData (M5) + Screen & Audio Recording (M6)
[ Week 4 ] ──▶ Cloud Storage & Sharing (M7) + Hardening, QA, Signing & Release (M8)
```

---

## 2. Detailed Milestone Breakdown

### Week 1: Core Shell, System Integration & Capture Engine

#### **Milestone 1: Foundation & App Shell** `[COMPLETED & VERIFIED]`
- **Target:** Days 1–3
- **Status:** ✅ **Completed & Verified**
- **Completion Sign-Off Checklist:**
  - [x] **Project Generation:** `project.yml` with XcodeGen generating `ScreenshotApp.xcodeproj` (deployment target macOS 14.0+).
  - [x] **SwiftPM Dual Support:** `Package.swift` configured for headless builds and tests.
  - [x] **App Lifecycle:** `ScreenshotApp.swift` (`@main`) with `NSApplicationDelegateAdaptor` and `AppDelegate.swift` controlling dock vs accessory policy.
  - [x] **Menu Bar Shell:** `MenuBarController.swift` with `NSStatusItem`, camera viewfinder template icon, capture shortcuts (`⇧⌘3`, `⇧⌘4`, `⇧⌘5`, `⇧⌘6`, `⇧⌘7`), storage mode status, recent items submenu, and settings launcher.
  - [x] **Settings Window:** Production-ready 7-tab `SettingsView.swift` (General, Capture, Shortcuts, Storage & Cloud, Privacy, Diagnostics with log viewer, About).
  - [x] **Unified Logging:** `AppLogger.swift` wrapping Apple `os.Logger` across 7 subsystems with regex token, secret key, and path redaction.
  - [x] **Typed Domain Errors:** `AppError.swift` with localized error messages, recovery suggestions, and `redactedDescription`.
  - [x] **Core Domain Models:** `ScreenshotAsset.swift`, `AnnotationDocument.swift` (with `NormalizedRect` 0.0-1.0 geometry), `UploadRecord.swift`, `MediaType.swift`.
  - [x] **Configuration:** `AppConfiguration.swift` and `CaptureSettings.swift` with `UserDefaults` persistence.
  - [x] **Unit Testing:** 10/10 unit tests passing in `ScreenshotAppTests` (`** TEST SUCCEEDED **`).
  - [x] **Build & Runtime Verification:** Built cleanly via `xcodebuild` to `./build/Build/Products/Debug/ScreenshotApp.app` and successfully launched on macOS (live running process verified).

---

#### **Milestone 2: Screen Capture Engine** `[COMPLETED & VERIFIED]`
- **Target:** Days 4–7
- **Status:** ✅ **Completed & Verified**
- **Completion Sign-Off Checklist:**
  - [x] **Permission Management:** `PermissionManager.swift` checking and requesting macOS Screen Recording permissions with deep-links to System Settings.
  - [x] **Capture Engine:** `ScreenCaptureService.swift` leveraging `ScreenCaptureKit` (`SCScreenshotManager`) with `CoreGraphics` fallback for full-display, targeted window, and cropped region captures.
  - [x] **Multi-Display Region Overlay:** `RegionSelectionOverlay.swift` presenting transparent `.screenSaver` windows across all displays with animated crosshairs, selection cutouts, and dynamic dimension badges.
  - [x] **Interactive Window Selection:** `WindowSelectionOverlay.swift` providing window hover detection and highlight bounding boxes.
  - [x] **Capture Pipeline & Post-Processing:** `CaptureCoordinator.swift` managing audio shutter feedback, automatic clipboard copying, file persistence to user-configured directory, and `ScreenshotAsset` creation.
  - [x] **Global Hotkeys:** `HotKeyManager.swift` intercepting `⇧⌘4` (Region), `⇧⌘3` (Full Screen), `⇧⌘5` (Window), `⇧⌘6` (Recording), and `⇧⌘7` (OCR) from any active application.
  - [x] **Unit Testing:** 14/14 unit tests passing in `ScreenshotAppTests` including coordinate conversion, sub-pixel geometry validation, and PNG/JPEG export verification (`** TEST SUCCEEDED **`).

---

### Week 2: Editing, Privacy Redaction, Styling & Vision

#### **Milestone 3: Annotation Editor & True Redaction** `[READY TO IMPLEMENT]`
- **Target:** Days 8–11
- **Status:** 🟡 **Next Up (Ready to start)**
- **Technical Plan & Files to Implement:**
  1. `Sources/Features/Editor/EditorWindowController.swift`: Dedicated AppKit window controller managing the editor canvas and toolbar.
  2. `Sources/Features/Editor/AnnotationCanvasView.swift`: SwiftUI / AppKit interactive vector canvas supporting tool selection, layer creation, drag selection, and handles.
  3. `Sources/Features/Editor/Tools/`: Vector annotation tool implementations (Arrow, Rectangle, Ellipse, Text, Semi-transparent Highlight, Freehand pen).
  4. `Sources/Features/Privacy/RedactionRenderer.swift`: Irreversible pixel rasterizer applying Gaussian blur and mosaic pixelation directly to base pixels.
  5. `Sources/Features/Editor/UndoRedoManager.swift`: Snapshot/action undo and redo stack.
  6. `Sources/Features/Editor/ExportCompositor.swift`: Core Graphics renderer generating flattened PNG/JPEG exports without unredacted data or hidden vector layers.

#### **Milestone 4: Image Styling & Local Recognition**
- **Target:** Days 12–14
- **Scope:**
  - [ ] `ImageComposer` for social/presentation styling: solid colors, modern gradient presets, padding, rounded corners, drop shadows.
  - [ ] On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest`).
  - [ ] Quick copy recognized text to clipboard.
  - [ ] QR code and barcode detection (`VNDetectBarcodesRequest`).
  - [ ] Zero cloud transmission guarantee for local text processing.

---

### Week 3: Storage, History & Screen Recording

#### **Milestone 5: Local History & Metadata Store**
- **Target:** Days 15–17
- **Scope:**
  - [ ] SwiftData schema for persistent asset indexing and search.
  - [ ] Full-text search across titles, tags, and recognized OCR text.
  - [ ] Media file lifecycle management in `~/Library/Application Support/com.screenshotapp.mac`.
  - [ ] History browser UI with thumbnail grid, date filters, and type filtering.
  - [ ] Local storage quota visualizer and one-click cache cleanup.
  - [ ] Missing file recovery and stale database record pruning.

#### **Milestone 6: Screen & Audio Recording**
- **Target:** Days 18–21
- **Scope:**
  - [ ] `RecordingCoordinator` based on `ScreenCaptureKit` stream APIs.
  - [ ] Region, window, and full screen video capture.
  - [ ] Microphone voiceover capture with privacy permissions check.
  - [ ] Menu bar recording indicator with elapsed duration timer and pause/stop controls.
  - [ ] Hardware-accelerated H.264/HEVC MP4 video export via `AVFoundation`.
  - [ ] Animated GIF conversion pipeline with frame rate and resolution controls.
  - [ ] Disk-space guard preventing recording exhaustion.

---

### Week 4: Cloud Sharing, Hardening, Signing & Launch

#### **Milestone 7: Cloud Storage & Instant Sharing**
- **Target:** Days 22–25
- **Scope:**
  - [ ] `CloudStorageProvider` actor protocol abstraction.
  - [ ] User-owned Amazon S3 / S3-compatible provider adapter (endpoint, bucket, region, credentials via macOS Keychain).
  - [ ] Managed Cloud backend client (presigned upload URLs, quotas, share tokens).
  - [ ] Upload progress indicator and automatic link copying.
  - [ ] Provider capability flags (deletion, link revocation, expiration).
  - [ ] Offline resilience: queue uploads if network is disconnected.

#### **Milestone 8: Production Hardening, Testing, Signing & Release**
- **Target:** Days 26–30
- **Scope:**
  - [ ] Full end-to-end test pass across all feature workflows.
  - [ ] High-resolution multi-monitor stress testing.
  - [ ] Memory leak audit with Instruments.
  - [ ] Apple Developer ID Application code signing (`codesign`).
  - [ ] Apple Notarization service submission (`xcrun notarytool submit`).
  - [ ] Staple notarization ticket (`xcrun stapler staple`).
  - [ ] Package release DMG with custom background, drag-to-Applications symlink, and checksum verification.
  - [ ] Final release verification on clean macOS installation.

---

## 3. Milestone Tracking Matrix

| Milestone | Target Days | Status | Unit Tests | Integration Tests |
|---|---|:---:|:---:|:---:|
| **M1: Foundation & App Shell** | Days 1–3 | **Done** | Pass | Pass |
| **M2: Capture Engine** | Days 4–7 | In Progress | Planned | Planned |
| **M3: Annotation & Redaction** | Days 8–11 | Planned | Planned | Planned |
| **M4: Styling & Recognition** | Days 12–14 | Planned | Planned | Planned |
| **M5: Local History & Database** | Days 15–17 | Planned | Planned | Planned |
| **M6: Screen Recording & GIF** | Days 18–21 | Planned | Planned | Planned |
| **M7: Cloud Storage & Sharing** | Days 22–25 | Planned | Planned | Planned |
| **M8: Hardening & Distribution** | Days 26–30 | Planned | Planned | Planned |

---

## 4. Production Acceptance Criteria ("Definition of Done")

1. **Local-First Reliability:** Every capture, annotation, styling, OCR, and history feature works with 100% functionality offline without requiring an account.
2. **True Redaction Guarantee:** Flattened exported images never contain original sensitive pixel data under blur or pixelation zones.
3. **No Unintended Uploads:** Uploading is never automatic unless explicitly configured by the user.
4. **Security & Credentials:** User credentials (S3 keys, tokens) are stored exclusively in macOS Keychain.
5. **Zero Memory Leaks:** Capture overlay windows and recording streams are properly deallocated after dismissal.
6. **Gatekeeper Ready:** Signed with Apple Developer ID, notarized without warnings, and mounts smoothly via DMG.
