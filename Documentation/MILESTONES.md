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

#### **Milestone 1: Foundation & App Shell** `[COMPLETED]`
- **Target:** Days 1–3
- **Scope:**
  - [x] Native SwiftUI + AppKit hybrid architecture.
  - [x] macOS 14.0+ deployment target configuration.
  - [x] `AppCoordinator` and `AppDelegate` lifecycle management.
  - [x] Menu-bar controller (`NSStatusItem`) with dynamic capture actions and status display.
  - [x] Production-ready multi-tab Settings window (General, Capture, Shortcuts, Storage, Privacy, Diagnostics, About).
  - [x] Unified logging facility (`AppLogger`) with automatic credential/token/path redaction.
  - [x] Typed domain errors (`AppError`) with recovery suggestions and redacted descriptions.
  - [x] Core domain models (`ScreenshotAsset`, `AnnotationDocument`, `UploadRecord`, `NormalizedRect`).
  - [x] Dual build support (`XcodeGen` + `ScreenshotApp.xcodeproj` and `Package.swift`).
  - [x] Unit test suite for foundation, configuration, and logging.

#### **Milestone 2: Screen Capture Engine** `[IN PROGRESS]`
- **Target:** Days 4–7
- **Scope:**
  - [ ] Implement `ScreenCaptureKit` and `CGPreflightScreenCaptureAccess` permissions flow.
  - [ ] Transparent multi-display AppKit overlay window for interactive region selection with crosshairs and dimension labels.
  - [ ] Full-display capture with Retina @2x scaling support.
  - [ ] Targeted window capture with automatic window boundary detection and shadow inclusion.
  - [ ] Configurable global hotkeys (`Carbon.HIToolbox` / `NSEvent.addGlobalMonitorForEvents`).
  - [ ] Shutter audio effect and optional clipboard auto-copy.
  - [ ] Integration tests for multi-display coordinate conversion.

---

### Week 2: Editing, Privacy Redaction, Styling & Vision

#### **Milestone 3: Annotation Editor & True Redaction**
- **Target:** Days 8–11
- **Scope:**
  - [ ] Canvas-based annotation editor window with undo/redo stack.
  - [ ] Vector annotation tools: Arrow, Rectangle, Ellipse, Text, Semi-transparent Highlight, Freehand pen.
  - [ ] True pixel-level redaction (Gaussian Blur & Mosaic Pixelation).
  - [ ] Document model persistence: vector layers saved separately from base raw capture.
  - [ ] Non-destructive cropping tool.
  - [ ] Flattened export rendering via Core Graphics/Core Image (ensuring redacted areas are irreversibly baked).

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
