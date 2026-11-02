import SwiftUI
import PencilKit

/// Handwriting-to-LaTeX input: a PencilKit canvas with a floating result tray.
///
/// The view fills whatever space its container gives it and adapts to any size, so it
/// works in full screen, Split View, Stage Manager, and while folding or unfolding.
/// Place standard controls such as Clear in the host's toolbar.
struct MathInputView: View {
    @Bindable var session: MathInputSession

    @State private var toolPicker = PKToolPicker()
    @State private var trayHeight: CGFloat = 0

    var body: some View {
        // The tray floats over the canvas instead of sitting below it, so the canvas
        // keeps a constant size while the tray grows and shrinks with each result.
        CanvasView(drawing: $session.drawing, toolPicker: toolPicker, bottomInset: trayHeight)
            .id(session.canvasID)
            .overlay(alignment: .bottom) {
                ResultPanel(
                    latex: session.latex,
                    errorMessage: session.errorMessage,
                    isRecognizing: session.isRecognizing,
                    canRecognize: session.canRecognize
                ) {
                    Task { await session.recognize() }
                }
                .padding([.horizontal, .bottom])
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trayHeight = $0 }
            }
            .task {
                await session.loadRecognizer()
            }
    }
}
