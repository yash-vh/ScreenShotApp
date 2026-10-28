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

#### **Milestone 3: Annotation Editor & True Redaction** `[COMPLETED & VERIFIED]`
- **Target:** Days 8–11
- **Status:** ✅ **Completed & Verified**
- **Completion Sign-Off Checklist:**
  - [x] **Irreversible Redaction Engine:** `RedactionRenderer.swift` utilizing GPU-accelerated Core Image filters (`CIGaussianBlur`, `CIPixellate`) that permanently overwrite and degrade pixel values in-place so redacted content is non-recoverable.
  - [x] **Snapshot Undo/Redo System:** `UndoRedoManager.swift` supporting multi-step undo (`⌘Z`), redo (`⇧⌘Z`), history trimming, and atomic document mutations.
  - [x] **Interactive Vector Canvas:** `AnnotationCanvasView.swift` supporting real-time drawing of Arrows, Rectangles, Ellipses, Text boxes, Semi-transparent Highlights, Freehand strokes, and live Blur/Pixelation overlays in normalized `0.0...1.0` coordinate space.
  - [x] **Modern Editor Toolbar:** `EditorToolbarView.swift` with tool pickers, harmonious 8-color palette, stroke width adjustments, undo/redo triggers, and instant Copy/Save actions.
  - [x] **Flattened Export Compositor:** `ExportCompositor.swift` rendering base image, baked pixel redactions, and vector annotation layers into flattened PNG/JPEG assets without retaining hidden vector layers.
  - [x] **Editor Window Management:** `EditorWindowController.swift` presenting native macOS editing windows scaled proportionally to captured asset dimensions.
  - [x] **Unit Testing:** 19/19 unit tests passing across all suites including `RedactionRendererTests`, `UndoRedoTests`, and `ExportCompositorTests` (`** TEST SUCCEEDED **`).

---

#### **Milestone 4: Image Styling & Local Recognition** `[COMPLETED & VERIFIED]`
- **Target:** Days 12–14
- **Status:** ✅ **Completed & Verified**
- **Completion Sign-Off Checklist:**
  - [x] **Image Composer:** `Styling/ImageComposer.swift` composes the flattened capture onto a backdrop with padding, rounded corners and drop shadow, scaled by the capture's pixels-per-point.
  - [x] **Background Presets:** `Styling/BackgroundPresets.swift` with 6 gradient + 2 solid presets; editor Style popover (palette button) with live canvas preview and undoable changes.
  - [x] **Vision Service:** `Recognition/VisionService.swift` runs on-device `VNRecognizeTextRequest` + `VNDetectBarcodesRequest` with reading-order sorting and text normalization. The accurate model is probed at launch and falls back to fast recognition on error/timeout.
  - [x] **OCR Result Overlay:** `Recognition/OCRResultOverlay.swift` shows text/QR boxes in the editor (⇧⌘T or toolbar), click-to-copy, "Copy All Text", "Copy QR Link", "Open Link".
  - [x] **Quick OCR capture:** ⇧⌘7 / ⌥⌘7 select a region and copy recognized text (or QR payload) with a confirmation HUD. Optional background OCR indexes `ocrText` on recent captures.
  - [x] **Unit Testing:** `ImageComposerTests`, `VisionServiceTests`.

#### **M1–M3 Stabilization Pass (post-review fixes)**
- [x] Editor: one undo step per drag/resize/nudge/slider scrub (was one per mouse event); selecting an item no longer writes history; no-op updates ignored.
- [x] Editor: move, 8-handle resize (⇧ keeps aspect), arrow endpoint editing, ⇧-constrained drawing, duplicate (⌘D), bring to front / send to back (⌘] / ⌘[), arrow-key nudge, right-click menu, delete button.
- [x] Editor: shortcuts handled via `performKeyEquivalent` so ⌘Z/⇧⌘Z/⌘C/⌘S/⌘D/⌘W work without a menu bar; Esc deselects then closes; Return edits text.
- [x] Editor: toolbar no longer under the traffic lights; toolbar ↔ selection style sync; inline text commit no longer duplicates; text editable in place with live color/size.
- [x] Export: annotations were vertically flipped and text was dropped; stroke/font sizes now scale with Retina pixel density.
- [x] Capture overlays: borderless overlay windows can become key (Esc/Return/⌘Z/typing now work); overlay annotations use the same y-down space as the editor; pixelate + "Open in Editor" (⌘E) added.
- [x] Capture: ScreenCaptureKit captures at native Retina resolution (was 1× and mis-cropped regions); full-screen capture uses the display under the pointer; "Save automatically to disk" is respected.
- [x] Hotkeys: Carbon hotkeys registered from Settings bindings (incl. custom capture shortcuts) and re-registered on change; ⇧-digit shortcuts recorded by key code (⇧⌘4 no longer saved as "$"); hotkeys suspended while recording a shortcut; ⌥⌘3–7 fallbacks.
- [x] Menu bar: shows configured shortcuts; Recent Captures / "Annotate Last Capture" open the editor; recording item no longer fakes a recording (M6).
- [x] Tests: `AnnotationCanvasInteractionTests`, `RegionOverlayAnnotationTests`, `ShortcutBindingTests`, extended `UndoRedoTests` / `ExportCompositorTests` — 50/50 passing.

---

### Week 3: Storage, History & Screen Recording

#### **Milestone 5: Local History & Metadata Store**
- **Target:** Days 15–17
- **Scope:**
  - [x] SwiftData schema for persistent asset indexing and search.
  - [x] Full-text search across titles, tags, and recognized OCR text.
  - [x] Media file lifecycle management in `~/Library/Application Support/com.screenshotapp.mac`.
  - [x] History browser UI with thumbnail grid, date filters, and type filtering.
  - [x] Local storage quota visualizer and one-click cache cleanup.
  - [x] Missing file recovery and stale database record pruning.

#### **Milestone 6: Screen & Audio Recording**
- **Target:** Days 18–21
- **Scope:**
  - [x] `RecordingCoordinator` based on `ScreenCaptureKit` stream APIs.
  - [x] Region, window, and full screen video capture.
  - [x] Microphone voiceover capture with privacy permissions check.
  - [x] Menu bar recording indicator with elapsed duration timer and pause/stop controls.
  - [x] Hardware-accelerated H.264/HEVC MP4 video export via `AVFoundation`.
  - [x] Animated GIF conversion pipeline with frame rate and resolution controls.
  - [x] Disk-space guard preventing recording exhaustion.

---

### Week 4: Cloud Sharing, Hardening, Signing & Launch

#### **Milestone 7: Cloud Storage & Instant Sharing**
- **Target:** Days 22–25
- **Scope:**
  - [x] `CloudStorageProvider` actor protocol abstraction.
  - [x] User-owned Amazon S3 / S3-compatible provider adapter (endpoint, bucket, region, credentials via macOS Keychain).
  - [x] Managed Cloud backend client (presigned upload URLs, quotas, share tokens).
  - [x] Upload progress indicator and automatic link copying.
  - [x] Provider capability flags (deletion, link revocation, expiration).
  - [x] Offline resilience: queue uploads if network is disconnected.

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
| **M2: Capture Engine** | Days 4–7 | **Done** | Pass | Pass |
| **M3: Annotation & Redaction** | Days 8–11 | **Done** | Pass | Pass |
| **M4: Styling & Recognition** | Days 12–14 | **Done** | Pass | Pass |
| **M5: Local History & Database** | Days 15–17 | **Done** | Pass | Pending |
| **M6: Screen Recording & GIF** | Days 18–21 | **Done** | Pass | Pending |
| **M7: Cloud Storage & Sharing** | Days 22–25 | **Done** (service not yet deployed) | Pass | Pending |
| **M8: Hardening & Distribution** | Days 26–30 | Planned | Planned | Planned |

---

## 4. Production Acceptance Criteria ("Definition of Done")

1. **Local-First Reliability:** Every capture, annotation, styling, OCR, and history feature works with 100% functionality offline without requiring an account.
2. **True Redaction Guarantee:** Flattened exported images never contain original sensitive pixel data under blur or pixelation zones.
3. **No Unintended Uploads:** Uploading is never automatic unless explicitly configured by the user.
4. **Security & Credentials:** User credentials (S3 keys, tokens) are stored exclusively in macOS Keychain.
5. **Zero Memory Leaks:** Capture overlay windows and recording streams are properly deallocated after dismissal.
6. **Gatekeeper Ready:** Signed with Apple Developer ID, notarized without warnings, and mounts smoothly via DMG.
