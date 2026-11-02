import SwiftUI
import PencilKit

/// A SwiftUI wrapper around `PKCanvasView` that reports its drawing through a binding.
///
/// Data flows one way: the canvas owns the strokes and publishes them to `drawing`.
/// To clear, give the view a new `.id` so SwiftUI creates a fresh canvas. Emptying a
/// canvas in place can leave stale ink on screen (PencilKit doesn't always repaint),
/// while a new canvas is guaranteed to start blank.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    /// Shared across canvases so the selected tool survives a clear.
    let toolPicker: PKToolPicker
    /// Height of UI floating over the bottom of the canvas, so ink beneath it can be scrolled into view.
    var bottomInset: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, toolPicker: toolPicker)
    }

    func makeUIView(context: Context) -> ExpandingCanvasView {
        let canvasView = ExpandingCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.tool = PKInkingTool(.pen, color: .black, width: PKInkingTool.InkType.pen.defaultWidth)
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true

        // mathdb is Apple Pencil only. Debug builds also accept mouse/finger so the simulator is usable.
        #if DEBUG
        canvasView.drawingPolicy = .anyInput
        #else
        canvasView.drawingPolicy = .pencilOnly
        #endif

        // Observing the tool picker keeps the canvas tool in sync with the palette.
        toolPicker.addObserver(canvasView)
        canvasView.pencilKitResponderState.activeToolPicker = toolPicker
        canvasView.pencilKitResponderState.toolPickerVisibility = .visible

        return canvasView
    }

    func updateUIView(_ canvasView: ExpandingCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        if canvasView.contentInset.bottom != bottomInset {
            canvasView.contentInset.bottom = bottomInset
            canvasView.verticalScrollIndicatorInsets.bottom = bottomInset
            canvasView.fitContentToInk()
        }
    }

    static func dismantleUIView(_ canvasView: ExpandingCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.removeObserver(canvasView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        let toolPicker: PKToolPicker

        init(drawing: Binding<PKDrawing>, toolPicker: PKToolPicker) {
            self.drawing = drawing
            self.toolPicker = toolPicker
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
            (canvasView as? ExpandingCanvasView)?.fitContentToInk()
        }
    }
}

/// A canvas whose scrollable area always covers all of its ink.
///
/// When the window gets smaller (Split View, Stage Manager, folding), ink that was
/// written near the far edge stays reachable by scrolling instead of being cut off.
final class ExpandingCanvasView: PKCanvasView {
    /// Room left past the furthest ink, so it isn't flush against the edge.
    private let margin: CGFloat = 80

    override func layoutSubviews() {
        super.layoutSubviews()
        fitContentToInk()
    }

    /// Sizes the scrollable area to the visible area, or to the ink if it extends further.
    func fitContentToInk() {
        let visibleWidth = bounds.width - adjustedContentInset.left - adjustedContentInset.right
        let visibleHeight = bounds.height - adjustedContentInset.top - adjustedContentInset.bottom
        let ink = drawing.strokes.isEmpty ? CGRect.zero : drawing.bounds
        let size = CGSize(width: max(visibleWidth, ink.maxX + margin),
                          height: max(visibleHeight, ink.maxY + margin))
        if contentSize != size {
            contentSize = size
        }
    }
}
