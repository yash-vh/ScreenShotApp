# ScreenMint Architecture Specification

## Overview

ScreenMint is a native macOS menu-bar-first application designed for capture, layered annotation, pixel-level redaction, on-device OCR, screen recording, and dual-mode cloud sharing (Managed Cloud vs User-Owned S3/Storage).

---

## Architectural Principles

1. **Separation of Concerns:** Feature modules (`Capture`, `Editor`, `Storage`, `Recognition`, `Recording`) are coordinated by high-level coordinators (`AppCoordinator`, `CaptureCoordinator`) and do not perform direct network or database calls.
2. **Local-First Guarantee:** Capture, vector annotations, background styling, OCR, and local asset history operate completely offline without network dependencies.
3. **Normalized Vector Geometry:** Annotation coordinates are stored in normalized space `[0.0 ... 1.0]`, allowing zoom, resizing, and responsive rendering regardless of display resolution or scale factors.
4. **Irreversible Redaction:** Blur and mosaic pixelation are permanently rasterized directly onto pixels during export rendering via Core Graphics/Core Image. Hidden layers or original pixels are never retained in flattened exports.
5. **Zero Secret Leakage:** Provider credentials and tokens are stored strictly in macOS Keychain. They are never written to `UserDefaults`, SwiftData, git commits, or crash logs.
6. **Privacy-Preserving Logs:** Unified logging (`os.Logger`) automatically filters and redacts authorization tokens, access keys, and user home directory paths.

---

## High-Level System Architecture

```mermaid
graph TD
    UI[SwiftUI & AppKit Shell]
    MenuBar[MenuBarController (NSStatusItem)]
    Settings[SettingsView (TabView)]
    
    Coordinator[AppCoordinator (MainActor)]
    
    CaptureEngine[Capture Module (ScreenCaptureKit / CG)]
    EditorEngine[Annotation Editor (Canvas / Core Graphics)]
    RecognitionEngine[Vision Framework (OCR / QR)]
    RecordingEngine[Recording Module (ScreenCaptureKit / AVFoundation)]
    
    LocalStorage[Local Asset Store (SwiftData / App Support)]
    StorageAbstraction[CloudStorageProvider Protocol]
    
    ManagedCloud[Managed Cloud Service Adapter]
    S3Provider[User-Owned S3 Adapter]
    
    UI --> MenuBar
    UI --> Settings
    MenuBar --> Coordinator
    Settings --> Coordinator
    
    Coordinator --> CaptureEngine
    Coordinator --> EditorEngine
    Coordinator --> RecognitionEngine
    Coordinator --> RecordingEngine
    
    EditorEngine --> LocalStorage
    RecordingEngine --> LocalStorage
    
    Coordinator --> StorageAbstraction
    StorageAbstraction --> ManagedCloud
    StorageAbstraction --> S3Provider
```

---

## Module Layout

- **`Sources/App/`**: Application lifecycle, `NSApplicationDelegate`, `AppCoordinator`, and `NSStatusItem` menu-bar integration.
- **`Sources/Core/Errors/`**: Typed `AppError` domains with localized descriptions and redacted diagnostic outputs.
- **`Sources/Core/Logging/`**: Apple `os.Logger` wrapper with in-memory buffer and token redaction.
- **`Sources/Core/Models/`**: Core data models (`ScreenshotAsset`, `AnnotationDocument`, `UploadRecord`, `MediaType`).
- **`Sources/Core/Configuration/`**: `AppConfiguration` managing persistent preferences and directory resolution.
- **`Sources/Features/Settings/`**: Modern tabbed settings interface adhering to macOS Human Interface Guidelines.
- **`Sources/Storage/`**: Local asset persistence, Keychain credential access, and cloud provider adapters.
