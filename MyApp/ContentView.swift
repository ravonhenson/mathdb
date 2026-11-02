import SwiftUI
import SwiftData

/// The app's top-level navigation. The system places the tab bar for each size:
/// at the bottom on iPhone, and wherever the platform prefers on larger displays.
struct ContentView: View {
    enum Destination: String {
        case home, sets, notes, settings
    }

    let notesSession: MathInputSession

    /// Restored per window, so the selected tab survives the app being closed.
    @SceneStorage("ContentView.selectedTab") private var selection = Destination.home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView { selection = .sets }
            }
            Tab("Sets", systemImage: "square.stack.3d.up", value: .sets) {
                SetsView()
            }
            Tab("Notes", systemImage: "note.text", value: .notes) {
                NotesView(session: notesSession)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView(notesSession: MathInputSession())
        .modelContainer(for: ProblemSet.self, inMemory: true)
}
