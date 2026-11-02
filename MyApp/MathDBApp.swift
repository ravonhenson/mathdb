import SwiftUI
import SwiftData

@main struct MathDBApp: App {
    /// The Notes tab's handwriting session; created once and restored from disk.
    @State private var notesSession = MathInputSession()

    var body: some Scene {
        WindowGroup {
            ContentView(notesSession: notesSession)
        }
        .modelContainer(for: ProblemSet.self)
    }
}
