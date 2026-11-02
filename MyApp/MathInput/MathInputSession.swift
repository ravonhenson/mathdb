import Foundation
import Observation
import PencilKit

/// The state behind `MathInputView`: the handwriting, its recognized LaTeX, and
/// recognition status. Changes are saved automatically so nothing is lost when the
/// app is closed or the window resizes.
@Observable
final class MathInputSession {
    var drawing: PKDrawing {
        didSet { scheduleSave() }
    }
    private(set) var latex: String {
        didSet { scheduleSave() }
    }
    private(set) var errorMessage: String?
    private(set) var isRecognizing = false
    /// Changes on every clear so the view swaps in a fresh, blank canvas (see `CanvasView`).
    private(set) var canvasID = 0

    var canRecognize: Bool {
        recognizer != nil && !drawing.strokes.isEmpty && !isRecognizing
    }

    var isEmpty: Bool {
        drawing.strokes.isEmpty && latex.isEmpty
    }

    @ObservationIgnored private var recognizer: MathRecognizer?
    @ObservationIgnored private let store: DrawingStore
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(store: DrawingStore = DrawingStore()) {
        self.store = store
        let saved = store.load()
        drawing = saved?.drawing ?? PKDrawing()
        latex = saved?.latex ?? ""
    }

    /// Loads the Core ML model. Safe to call more than once.
    func loadRecognizer() async {
        guard recognizer == nil else { return }
        do {
            recognizer = try await MathRecognizer.shared()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recognize() async {
        guard let recognizer, !isRecognizing else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            latex = try await recognizer.recognize(InkFeatures.strokes(from: drawing))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        drawing = PKDrawing()
        latex = ""
        errorMessage = nil
        canvasID += 1
    }

    /// Writes the current state to disk right away, e.g. when the app moves to the background.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try store.save(.init(drawing: drawing, latex: latex))
        } catch {
            // Saving is best effort; the in-memory state is unaffected.
            print("MathInputSession: couldn't save: \(error)")
        }
    }

    /// Saves shortly after the last change, so writing doesn't hit the disk on every stroke.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
