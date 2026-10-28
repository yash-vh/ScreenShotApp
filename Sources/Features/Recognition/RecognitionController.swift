import AppKit
import Combine

/// Drives the "Recognize Text & QR Codes" toggle for any annotation canvas (editor window or capture overlay):
/// runs on-device recognition on demand, caches the result, and shows / hides the `OCRResultOverlay`.
@MainActor
public final class RecognitionController {
    private let state: EditorState
    private weak var canvas: AnnotationCanvasView?
    private let imageProvider: () -> CGImage?

    private var overlay: OCRResultOverlay?
    private var cachedResult: RecognitionResult?
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(state: EditorState, canvas: AnnotationCanvasView, imageProvider: @escaping () -> CGImage?) {
        self.state = state
        self.canvas = canvas
        self.imageProvider = imageProvider

        state.$isShowingRecognition
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] showing in
                self?.setVisible(showing)
            }
            .store(in: &cancellables)

        // Styling padding moves the image inside the canvas; keep boxes aligned
        canvas.undoRedoManager.$document
            .sink { [weak self] _ in
                self?.overlay?.needsDisplay = true
                self?.overlay?.needsLayout = true
            }
            .store(in: &cancellables)
    }

    /// Drops cached results (call when the underlying image changes, e.g. the capture selection is resized)
    public func invalidate() {
        task?.cancel()
        task = nil
        cachedResult = nil
        state.isRecognizing = false
        if state.isShowingRecognition {
            state.isShowingRecognition = false
        }
        overlay?.removeFromSuperview()
        overlay = nil
    }

    private func setVisible(_ visible: Bool) {
        guard visible else {
            task?.cancel()
            task = nil
            state.isRecognizing = false
            overlay?.removeFromSuperview()
            overlay = nil
            return
        }
        if let cached = cachedResult {
            show(cached)
            return
        }
        guard let image = imageProvider() else {
            state.isShowingRecognition = false
            return
        }

        state.isRecognizing = true
        task = Task { @MainActor [weak self] in
            do {
                let result = try await VisionService.shared.recognize(in: image)
                guard let self = self, !Task.isCancelled else { return }
                self.state.isRecognizing = false
                self.cachedResult = result
                if self.state.isShowingRecognition {
                    self.show(result)
                }
            } catch {
                guard let self = self, !Task.isCancelled else { return }
                AppLogger.shared.recognition.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
                self.state.isRecognizing = false
                self.state.isShowingRecognition = false
                self.canvas?.showToast("Text recognition failed")
            }
        }
    }

    private func show(_ result: RecognitionResult) {
        guard let canvas = canvas, overlay == nil else { return }
        let view = OCRResultOverlay(result: result) { [weak canvas] in canvas?.imageRect ?? .zero }
        view.frame = canvas.bounds
        view.autoresizingMask = [.width, .height]
        view.onMessage = { [weak canvas] message in canvas?.showToast(message) }
        view.onClose = { [weak self] in self?.state.isShowingRecognition = false }
        canvas.addSubview(view)
        overlay = view

        if result.isEmpty {
            canvas.showToast("No text or QR codes found")
        }
    }
}
