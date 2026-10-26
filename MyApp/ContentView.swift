import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            CanvasView(drawing: $drawing)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("mathdb")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Strokes: \(drawing.strokes.count)")
                            .monospacedDigit()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "trash") {
                            drawing = PKDrawing()
                        }
                        .disabled(drawing.strokes.isEmpty)
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
