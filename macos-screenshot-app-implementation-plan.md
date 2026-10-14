# macOS Screenshot App — Implementation Plan and Technical Specification

**Platform:** macOS  
**Implementation:** Native SwiftUI + AppKit  
**Distribution:** Direct website download  
**Storage:** Managed cloud + user-owned cloud providers  
**V1 features:** Capture, annotations, blur/redaction, history, backgrounds, OCR/QR recognition, screen recording, cloud upload and sharing

---

## 1. Product vision

Build a fast, menu-bar-first macOS utility that lets users capture screenshots, annotate and style them, recognize text, record screen activity, keep a local history, and share assets through either the app's managed cloud service or their own storage provider.

**Primary workflow:** Capture → Annotate → Enhance → Upload → Copy link.

The app must remain useful without an account or internet connection. Local capture, editing, OCR, and history should work offline. Uploading must be an explicit user action unless the user deliberately enables an automatic-upload setting.

## 2. Goals and scope

### V1 goals

- Capture full displays, individual windows, and selected regions.
- Offer configurable global shortcuts and menu-bar controls.
- Annotate with arrows, shapes, text, freehand drawing, and highlights.
- Blur or pixelate sensitive regions with true pixel-level redaction on export.
- Add backgrounds, padding, rounded corners, and shadows.
- Run on-device OCR and QR-code recognition.
- Record supported screen content, with optional system audio and microphone input where permitted.
- Export recordings to a standard video format and offer GIF conversion.
- Maintain searchable local history for screenshots and recordings.
- Upload to managed hosting or a user-configured storage provider.
- Copy and open share links; delete remote assets or revoke links where supported.
- Distribute a signed and notarized build directly from a website.

### Explicitly out of scope for initial V1

- Team workspaces and collaboration.
- Web-based annotation editor.
- Mobile apps.
- Unlimited cloud storage.
- Automatic cloud sync across devices.
- Cloud OCR or AI processing.
- Enterprise administration and SSO.
- Custom domains and advanced analytics.

These can be considered after validating the core product.

## 3. Recommended stack

| Area | Choice |
|---|---|
| UI | SwiftUI |
| Native window and menu-bar integration | AppKit |
| Screen capture and recording | ScreenCaptureKit |
| Region selection | Transparent AppKit overlay windows |
| Annotation rendering | SwiftUI Canvas or a custom AppKit drawing view |
| Image composition | Core Graphics and Core Image |
| OCR and QR recognition | Vision framework |
| Local metadata | SwiftData |
| Media files | Application Support directory |
| Credentials | macOS Keychain |
| Networking | URLSession with async/await |
| Logging | OSLog with sensitive values redacted |
| Managed backend | Node.js + TypeScript |
| Backend database | PostgreSQL |
| Managed media storage | Private S3-compatible object storage |
| Distribution | Developer ID signing, notarization, DMG |

**Minimum macOS version:** provisionally macOS 14+. Verify API availability and the desired recording/audio behavior in a prototype before locking the deployment target.

## 4. Architecture

Keep the app modular and feature-oriented. The UI must not make cloud requests directly. Services should expose async APIs, cancellation, progress, and typed errors.

### High-level flow

1. SwiftUI views and AppKit windows present the menu bar, capture overlay, editor, history, and settings.
2. Feature services handle capture, annotation, export, OCR, recording, and sharing.
3. SwiftData stores metadata and references to local media files.
4. A local asset store manages media files.
5. A storage-provider abstraction routes uploads to either managed cloud or user-owned providers.
6. The managed backend handles authentication, quotas, upload authorization, share links, deletion, and retention.

### Architecture rules

- Keep the original capture separate from the editable annotation document and flattened export.
- Use normalized coordinates (`0...1`) for annotation positions.
- Keep large image/video blobs on disk, not in database records.
- Store provider credentials in Keychain, never in SwiftData, `UserDefaults`, source code, or logs.
- Keep provider-specific logic inside provider adapters.
- Use capability flags to avoid showing unsupported features such as password-protected links.
- Never embed privileged server credentials in the macOS binary.
- Ensure the app works locally when cloud services are unavailable.

## 5. Suggested repository structure

```text
ScreenshotApp/
├── ScreenshotApp.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── ScreenshotApp.swift
│   │   ├── AppDelegate.swift
│   │   ├── AppCoordinator.swift
│   │   └── MenuBarController.swift
│   ├── Core/
│   │   ├── Models/
│   │   ├── Errors/
│   │   ├── Logging/
│   │   ├── Utilities/
│   │   └── Configuration/
│   ├── Features/
│   │   ├── Capture/
│   │   ├── Editor/
│   │   ├── Privacy/
│   │   ├── Styling/
│   │   ├── Recognition/
│   │   ├── Recording/
│   │   ├── History/
│   │   ├── Sharing/
│   │   └── Settings/
│   ├── Storage/
│   │   ├── Local/
│   │   ├── Cloud/
│   │   └── Credentials/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Presets/
├── Tests/
│   ├── UnitTests/
│   ├── IntegrationTests/
│   └── PerformanceTests/
├── UITests/
├── Scripts/
│   ├── build-release.sh
│   └── package-dmg.sh
└── Documentation/
    ├── ARCHITECTURE.md
    ├── PRIVACY.md
    └── RELEASE.md
```

Treat this as logical organization. Do not create many separate Swift packages or targets without a concrete need.

## 6. Core domain models

### Screenshot asset

The model should include at least:

- Stable UUID.
- Creation and modification timestamps.
- Title and tags.
- Original local file URL.
- Optional flattened export URL.
- Pixel dimensions and file size.
- Optional OCR text.
- Media type (image, video, GIF).
- Upload records.
- Local availability/deletion state.

### Annotation document

Represent annotations as typed, Codable values with stable IDs and normalized coordinates.

Annotation types:

- Arrow.
- Rectangle and ellipse.
- Freehand path.
- Text.
- Highlight.
- Blur.
- Pixelation.

Each item may store color, stroke width, text/font properties, fill, points, and other type-specific attributes. Use custom Codable representations where framework types such as `CGPoint` or colors require them.

### Upload record

Track:

- Stable upload record ID.
- Provider ID.
- Remote object ID/key.
- Share URL, if one exists.
- Upload state and timestamps.
- Expiration time, if the provider supports it.
- Last error, safely redacted.
- Whether deletion or revocation is supported.

Do not use the share URL as the permanent identity of an uploaded object.

## 7. Feature specifications

### 7.1 Screenshot capture

Implement a `CaptureCoordinator` and a `ScreenCaptureService`.

Requirements:

- Full-display, window, and region capture.
- Configurable global shortcuts.
- Menu-bar commands.
- Multiple displays and Retina scaling.
- Hide capture overlays/toolbars from the final capture.
- Restore app focus after capture.
- Handle permission denial, cancellation, screen lock, display changes, and capture failures.
- Save the original file before opening the editor.
- Show useful permission instructions and errors.

Evaluate ScreenCaptureKit's source-selection APIs and a custom AppKit overlay for region selection. Verify current API availability during implementation.

**Acceptance criteria:** a user can capture from another app using a shortcut, select a region, and begin editing without manually finding the file.

### 7.2 Annotation editor

Use a document model with separate layers:

1. Base image.
2. Annotation objects.
3. Optional background/style layer.
4. Flattened export renderer.

Required tools:

- Arrow with adjustable direction and stroke.
- Rectangle and ellipse, with outline/fill.
- Text with font, size, alignment, and color.
- Semi-transparent highlight.
- Freehand drawing.
- Blur and pixelation.
- Undo/redo.
- Crop.
- Export to PNG and JPEG.

Store editable annotation data so the user can reopen and change annotations. Flatten only when rendering the final export.

**Privacy requirement:** hiding text under an opaque shape is not redaction. Blur/pixelation must modify exported pixels. The export must not contain unredacted originals or hidden layers that recover the redacted content.

### 7.3 Background and image styling

Build an `ImageComposer` supporting:

- Solid-color and gradient backgrounds.
- Preset backgrounds.
- Padding and rounded corners.
- Drop shadows and shadow softness.
- Canvas sizing and aspect-ratio controls.
- Reusable local presets.
- PNG/JPEG export.

Use Core Graphics/Core Image for rendering. Do not capture a screenshot of the editor UI to create an export.

### 7.4 OCR and QR recognition

Use the Vision framework locally.

OCR requirements:

- Run asynchronously.
- Optionally preserve text bounding boxes.
- Copy all recognized text.
- Index text for local history search.
- Allow OCR to be disabled.
- Do not upload recognized text unless explicitly included by the user.

QR requirements:

- Detect QR codes and display decoded content.
- Do not open decoded URLs automatically.
- Treat decoded content as untrusted input.

**Acceptance criteria:** searching for text visible in a previous screenshot finds that screenshot, without sending the image to a remote OCR service.

### 7.5 Screen recording

Use a dedicated `RecordingCoordinator` and recording service based on ScreenCaptureKit.

Requirements:

- Record a supported display, window, or region.
- Start, pause/resume where supported, and stop.
- Show a visible recording indicator and elapsed time.
- Support system audio and microphone only where supported and explicitly enabled.
- Save the recording locally before optional upload.
- Export to a standard video format such as MP4.
- Offer GIF conversion as a separate export step.
- Handle disk-space errors, permission revocation, display changes, and failed recording sessions.
- Keep encoding and file I/O off the main thread.

Test audio synchronization and repeated start/stop cycles. Define a maximum recording duration or disk-space guard for the initial release.

**Acceptance criteria:** a recording can be stopped cleanly, previewed, saved locally, and exported without freezing the UI.

### 7.6 Local history

Use SwiftData for metadata and the filesystem for media.

Requirements:

- Recent screenshots, videos, and GIFs.
- Search by title, OCR text, and tags.
- Filters by date, type, and upload status.
- Reopen an image in the editor.
- Copy image or share link.
- Re-upload to another provider.
- Delete local files and cloud objects separately.
- Show local storage usage and offer cleanup controls.
- Recover gracefully if a file is missing or the database record is stale.

Use stable asset IDs to associate records with files. Database and filesystem updates must be resilient to interruption.

## 8. Cloud storage design

Managed hosting and user-owned storage must use the same provider interface, but separate authentication and authorization flows.

### 8.1 Provider abstraction

Define a `CloudStorageProvider` protocol with methods equivalent to:

- `upload(fileURL:options:) async throws -> UploadResult`
- `delete(objectID:) async throws`
- `createShareLink(objectID:options:) async throws -> URL`

Add typed options/results, upload progress, cancellation, and provider capability metadata. The exact Swift protocol may need adjustment for actor isolation and `Sendable` constraints.

Provider capabilities must explicitly indicate whether the provider supports:

- Delete.
- Expiring links.
- Password-protected links.
- Private or public objects.
- Multipart/resumable uploads.
- Link revocation.

Do not promise features a provider does not support.

### 8.2 Managed cloud backend

Suggested backend:

- Node.js + TypeScript API.
- PostgreSQL for users, uploads, quotas, links, and retention metadata.
- Private S3-compatible object storage.
- HTTPS-only API.
- Short-lived upload authorization.
- Public share page or controlled download endpoint.
- Scheduled deletion of expired assets and abandoned multipart uploads.

Recommended endpoints (adapt names and methods during implementation):

```text
POST   /v1/uploads/initiate
POST   /v1/uploads/:id/complete
GET    /v1/uploads/:id
DELETE /v1/uploads/:id

POST   /v1/shares
GET    /s/:shareToken
DELETE /v1/shares/:shareId

GET    /v1/account/usage
GET    /v1/providers
```

Define authentication and ownership checks for every endpoint. Do not expose internal database IDs as sufficient authorization.

### 8.3 Managed upload flow

1. User chooses Managed Cloud and selects an asset.
2. The app sends file metadata and intended upload settings to the API.
3. The API authenticates the user or applies anonymous-upload quotas.
4. The API returns a short-lived, narrowly scoped upload URL/session.
5. The app uploads directly to object storage.
6. The app calls the completion endpoint.
7. The backend verifies the completed object, records metadata, and creates a share record if requested.
8. The app displays the share link and copies it only according to user settings.

Avoid sending all large video bytes through the application API server. Verify upload completion before publishing a share link. Treat presigned URLs as bearer credentials and keep them short-lived.

### 8.4 User-owned providers

Implement provider adapters independently. Prioritize S3-compatible storage first, then add Cloudinary or Supabase Storage after verifying their current APIs, account requirements, pricing, and sharing behavior.

For S3-compatible storage, settings may include:

- Endpoint.
- Region.
- Bucket.
- Access key and secret key, or a supported alternative credential flow.
- Optional path prefix.
- Public/private sharing mode, where supported.

Validate endpoint URLs and TLS. Restrict redirects and avoid sending credentials to unexpected hosts. Explain the permissions required for each provider.

For Cloudinary or Supabase, use their supported authentication and upload mechanisms. Do not assume they behave identically to S3.

### 8.5 Credentials and settings

- Store secrets in macOS Keychain.
- Never store credentials in source code, `UserDefaults`, SwiftData, plain configuration files, or logs.
- Provide test connection, disconnect, and credential removal.
- Do not transmit user-owned provider credentials to the managed backend.
- Show storage mode clearly: **Local only**, **Managed cloud**, or **My storage**.
- Default to local-only operation until the user configures or chooses a cloud destination.

### 8.6 Sharing behavior

Keep object identity separate from share-link identity.

- Deleting a share link is not necessarily deleting the object.
- Deleting an object may invalidate links, depending on provider behavior.
- Expiration may apply to the link, the object, or both; show the actual semantics.
- Do not claim that link revocation removes copies already downloaded by recipients.
- Use unguessable share tokens, authorization checks, rate limits, and HTTPS.

## 9. Security and privacy requirements

Screenshots may contain sensitive personal or business information.

- Local-first by default.
- Upload only after explicit user action unless the user enables a clearly disclosed automatic-upload setting.
- Request screen-capture permission only when needed.
- Request microphone permission only when microphone recording is enabled.
- Use HTTPS for all network requests.
- Keep managed storage private by default.
- Use short-lived, narrowly scoped upload credentials.
- Validate file type, size, quota, and ownership on the backend.
- Rate-limit anonymous uploads and public share endpoints.
- Prevent path traversal and arbitrary object-key access.
- Redact tokens, URLs containing credentials, and sensitive content from logs.
- Do not upload OCR text or thumbnails without appropriate consent.
- Implement deletion, retention, and abandoned-upload cleanup.
- Publish privacy, retention, and support pages.
- Test cross-user authorization and share-link revocation.
- Ensure redaction is irreversible in the flattened export.

## 10. Testing strategy

### Unit tests

- Annotation geometry and normalized-coordinate conversion.
- Undo/redo state transitions.
- Image composition and export dimensions.
- OCR result normalization and indexing.
- Upload state transitions and retry rules.
- Provider capability handling.
- Database/filesystem reconciliation.
- Keychain wrapper behavior.

### Integration tests

- Capture permissions and successful capture.
- Multi-display/Retina behavior.
- Recording lifecycle and audio options.
- Managed upload initiation, completion, and deletion.
- User-owned provider upload and sharing.
- Expiration and revocation where supported.
- Interrupted uploads and retries.
- Missing local files and interrupted database updates.

### UI tests

- First launch and permission education.
- Capture-to-editor workflow.
- Annotation, blur, and export.
- History search and reopen.
- Provider setup and disconnect.
- Upload progress, failure, retry, and copy-link.
- Recording start/stop and preview.
- Settings and privacy controls.

### Performance/reliability tests

- High-resolution screenshots on multiple displays.
- Large image/video export without excessive memory growth.
- Full disk and network timeout handling.
- Repeated recording start/stop.
- App restart after interrupted operations.
- Cloud-provider outage and expired credentials.

### Definition of done

All requested feature groups work end to end. Local capture/edit/history works offline. Uploads require explicit authorization. Redaction tests pass. The app handles missing permissions, disk errors, network failures, and missing files gracefully. A signed and notarized package installs on a clean supported Mac.

## 11. Development milestones

Plan for approximately 6–8 weeks for a focused solo-developer MVP. These estimates are not guarantees and depend on recording complexity and cloud setup.

| Milestone | Estimate | Deliverable | Status |
|---|---:|---|:---:|
| M1. Foundation | 3–4 days | Xcode project, lifecycle, menu bar, settings | ✅ **Completed** |
| M2. Capture | 4–5 days | Full-screen, window, region capture | 🟡 **Next Up** |
| M3. Editor | 5–7 days | Annotations, undo/redo, blur/pixelation | ⚪️ Planned |
| M4. Styling + recognition | 3–4 days | Backgrounds, export, OCR, QR | ⚪️ Planned |
| M5. History | 2–3 days | Database, search, file management | ⚪️ Planned |
| M6. Recording | 5–7 days | Screen/audio capture, export, GIF conversion | ⚪️ Planned |
| M7. Cloud | 5–7 days | Managed service, S3-compatible provider, sharing | ⚪️ Planned |
| M8. QA + release | 4–5 days | Testing, signing, notarization, website release | ⚪️ Planned |

### Recommended implementation sequence

1. Build a working capture prototype.
2. Add a persistent annotation document and export compositor.
3. Add local history and OCR.
4. Implement managed cloud upload and sharing.
5. Implement one user-owned provider (S3-compatible).
6. Implement recording and GIF export as a separate pipeline.
7. Add provider adapters only after end-to-end tests pass.
8. Complete privacy, performance, and release checks.

Keep milestones independently testable. Validate ScreenCaptureKit permission behavior, recording/audio, and cloud sharing early.

## 12. Direct website distribution

Release a Developer ID-signed, notarized macOS application.

Checklist:

- [ ] Set bundle identifier, version, and build number.
- [ ] Configure usage descriptions and required entitlements.
- [ ] Enable hardened runtime as required.
- [ ] Create/use a Developer ID Application signing identity.
- [ ] Test on a clean Mac with normal Gatekeeper settings.
- [ ] Run unit, integration, UI, performance, and privacy tests.
- [ ] Build and export the release archive.
- [ ] Submit the exact release artifact for notarization.
- [ ] Verify notarization and staple the ticket where applicable.
- [ ] Package the app in a DMG with clear install instructions.
- [ ] Publish checksums, release notes, and minimum macOS version.
- [ ] Publish privacy policy, retention policy, and support contact.
- [ ] Verify update delivery and rollback procedures.

Suggested release artifacts:

```text
release/
├── ScreenshotApp-1.0.0.dmg
├── ScreenshotApp-1.0.0.dmg.sha256
├── RELEASE_NOTES.md
└── INSTALL.md
```

Test the exact packaged artifact after signing and notarization. Do not distribute a development build or one with unnecessary debugging entitlements.

## 13. Release checklist

- [ ] Full-screen, window, and region capture work.
- [ ] Shortcuts are configurable and do not break common system shortcuts.
- [ ] Multi-display and Retina captures are correct.
- [ ] Annotation document reopens correctly.
- [ ] Blur/pixelation exports do not retain recoverable original pixels.
- [ ] Backgrounds and exports render at correct dimensions.
- [ ] OCR/QR processing works locally and respects settings.
- [ ] Recording, audio options, video export, and GIF conversion are tested.
- [ ] History search, missing-file recovery, and cleanup work.
- [ ] Managed upload, share link, deletion, and quotas work.
- [ ] User-owned provider credentials are securely stored.
- [ ] Upload retry/cancellation and expired credentials are handled.
- [ ] Privacy and retention policies are published.
- [ ] Signing, notarization, Gatekeeper installation, and updates are verified.
- [ ] Website download, checksum, release notes, and support contact are live.

## 14. Decisions to make during implementation

Keep these configurable until the relevant prototype or cost test is complete:

- Final minimum macOS version.
- Final app name and bundle identifier.
- Global shortcut defaults.
- Managed-cloud authentication model (anonymous quota vs account-based).
- Storage provider and actual free-tier limits.
- Maximum upload size and recording duration.
- Whether audio recording is in the first public build.
- Whether GIF conversion uses a built-in pipeline or a bundled external tool.
- Whether updates are delivered through a signed updater or manual download.
- Paid-plan pricing, quotas, and retention rules.

Do not promise unlimited free cloud storage before measuring storage, bandwidth, and egress costs.

## 15. Instructions for the AI coding agent

Implement this project incrementally. Do not try to generate the entire application in one pass.

1. Inspect the existing repository before changing files.
2. If the repository is empty, create the native macOS Xcode project and document the selected deployment target.
3. Implement one milestone at a time in the order described above.
4. Before each milestone, list the files to add/change and summarize the approach.
5. Keep the app compiling after each milestone.
6. Use native Apple APIs and current documented SDK behavior; verify API availability rather than inventing methods.
7. Add unit tests alongside core models and services.
8. Do not leave fake cloud uploads or placeholder success states. If backend configuration is missing, show a clear setup/error state.
9. Never place secrets in source code. Include an `.env.example` only for backend configuration and ensure real secret files are ignored by Git.
10. Keep UI work accessible, keyboard-friendly, and consistent with macOS conventions.
11. Handle cancellation, progress, and errors for long-running tasks.
12. Document setup, permissions, architecture, provider configuration, testing, and release commands.
13. At the end of each milestone, report changed files, tests run, results, and remaining issues.
14. Ask for clarification only when a decision blocks safe or correct implementation; otherwise use the documented defaults and record assumptions.

### First task for the coding agent

**Milestone 1 only:** inspect the repository, establish the native SwiftUI + AppKit app structure, configure the provisional deployment target, implement a menu-bar app shell and settings window, add logging/error-handling foundations, and create a build/test checklist. Do not implement cloud uploads or the entire feature set in the first task.
