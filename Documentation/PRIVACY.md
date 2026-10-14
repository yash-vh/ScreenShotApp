# Privacy and Data Protection Policy

## 1. Local-First Architecture
ScreenshotApp is built on a local-first paradigm. All screen capture, vector annotation, styling, on-device OCR, and asset indexing happen entirely on your Mac. No network request is initiated without explicit user consent.

## 2. Irreversible Redaction Guarantee
Hiding sensitive text or images behind an overlay shape is not true redaction. In ScreenshotApp:
- Blur (Gaussian filter) and pixelation (mosaic) are permanently rasterized directly into image pixels upon export.
- The flattened export file does not include vector layers, original unblurred image buffers, or hidden alpha channels that could reconstruct sensitive data.

## 3. On-Device OCR & Vision Processing
Text recognition and QR/barcode detection utilize Apple's native Vision framework (`VNRecognizeTextRequest`). Text processing is performed entirely on the Neural Engine/GPU of your Mac. Recognized text is indexed locally via SwiftData and is never uploaded to any remote server or AI service.

## 4. Cloud Provider Credentials
Credentials for user-owned providers (Amazon S3 access keys, Supabase tokens, etc.) are stored exclusively in the macOS Keychain. Credentials are never written to disk files, database tables, or logging outputs.
