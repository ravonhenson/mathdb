import SwiftUI
import PencilKit

/// Enter LaTeX by writing it with Apple Pencil.
///
/// Recognition runs automatically shortly after you stop writing, with a live preview.
/// The result fills an empty field, or replaces or is appended to existing text.
struct HandwritingLaTeXSheet: View {
    let title: String
    @Binding var text: String

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    /// Changes on clear so a fresh, blank canvas is created (see `CanvasView`).
    @State private var canvasID = 0
    @State private var toolPicker = PKToolPicker()
    @State private var latex = ""
    @State private var errorMessage: String?
    @State private var isRecognizing = false
    @State private var trayHeight: CGFloat = 0

    /// How long to wait after the last stroke before recognizing.
    private static let pause = Duration.milliseconds(600)

    var body: some View {
        NavigationStack {
            CanvasView(drawing: $drawing, toolPicker: toolPicker, bottomInset: trayHeight)
                .id(canvasID)
                .overlay {
                    if drawing.strokes.isEmpty {
                        Label("Write with Apple Pencil", systemImage: "pencil.and.scribble")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) {
                    resultTray
                        .padding([.horizontal, .bottom])
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trayHeight = $0 }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", systemImage: "trash", action: clear)
                            .disabled(drawing.strokes.isEmpty)
                    }
                }
                .task(id: drawing) {
                    await recognizeAfterPause()
                }
        }
    }

    private var resultTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if latex.isEmpty {
                Text(isRecognizing ? "Reading your handwriting…" : "Your LaTeX will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                LaTeXView(latex: latex, maxHeight: 160)
                Text(latex)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            HStack {
                if isRecognizing && !latex.isEmpty {
                    ProgressView()
                }
                Spacer()
                if text.isEmpty {
                    Button("Use") { insert(replacing: true) }
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Append") { insert(replacing: false) }
                        .buttonStyle(.glass)
                    Button("Replace") { insert(replacing: true) }
                        .buttonStyle(.glassProminent)
                }
            }
            .disabled(latex.isEmpty || isRecognizing)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 20), isUniform: true))
    }

    private func recognizeAfterPause() async {
        guard !drawing.strokes.isEmpty else {
            latex = ""
            errorMessage = nil
            return
        }
        // Cancelled (and restarted) whenever the drawing changes, so this waits for a pause.
        try? await Task.sleep(for: Self.pause)
        guard !Task.isCancelled else { return }

        isRecognizing = true
        defer { isRecognizing = false }
        do {
            let recognizer = try await MathRecognizer.shared()
            let result = try await recognizer.recognize(InkFeatures.strokes(from: drawing))
            guard !Task.isCancelled else { return }
            latex = result
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func insert(replacing: Bool) {
        text = replacing || text.isEmpty ? latex : "\(text) \(latex)"
        dismiss()
    }

    private func clear() {
        drawing = PKDrawing()
        latex = ""
        errorMessage = nil
        canvasID += 1
    }
}

#Preview {
    @Previewable @State var text = ""
    HandwritingLaTeXSheet(title: "Write Answer", text: $text)
}
