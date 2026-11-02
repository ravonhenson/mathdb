import SwiftUI

/// For now, the handwriting-to-LaTeX proof of concept.
struct NotesView: View {
    let session: MathInputSession

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MathInputView(session: session)
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "trash") {
                            session.clear()
                        }
                        .disabled(session.isEmpty)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Save immediately when leaving the foreground; the app may be closed next.
            if phase != .active {
                session.saveNow()
            }
        }
    }
}
