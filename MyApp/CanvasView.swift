import SwiftUI
import PencilKit

/// A SwiftUI wrapper around `PKCanvasView` that keeps a `PKDrawing` binding in sync
/// and shows the system tool picker.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawing = drawing
        canvasView.tool = PKInkingTool(.pen, color: .black, width: PKInkingTool.InkType.pen.defaultWidth)
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true

        // Allow mouse/finger drawing in Debug so the simulator is usable; prefer Pencil in Release.
        #if DEBUG
        canvasView.drawingPolicy = .anyInput
        #else
        canvasView.drawingPolicy = .default
        #endif

        // The canvas owns its tool picker; observing it keeps the canvas tool in sync with the palette.
        let toolPicker = context.coordinator.toolPicker
        toolPicker.addObserver(canvasView)
        canvasView.pencilKitResponderState.activeToolPicker = toolPicker
        canvasView.pencilKitResponderState.toolPickerVisibility = .visible

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        // Only push external changes (e.g. Clear) to avoid resetting the canvas mid-stroke.
        if canvasView.drawing != drawing {
            canvasView.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        let toolPicker = PKToolPicker()

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
