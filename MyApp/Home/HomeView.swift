import SwiftUI
import SwiftData

/// The landing tab: recently changed sets, so you can pick up where you left off.
struct HomeView: View {
    /// Switches to the Sets tab.
    var showSets: () -> Void = {}

    @Query(Self.recentSetsDescriptor) private var recentSets: [ProblemSet]

    private static var recentSetsDescriptor: FetchDescriptor<ProblemSet> {
        var descriptor = FetchDescriptor<ProblemSet>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    var body: some View {
        NavigationStack {
            Group {
                if recentSets.isEmpty {
                    ContentUnavailableView {
                        Label("Welcome to mathdb", systemImage: "pencil.and.scribble")
                    } description: {
                        Text("Create a problem set, then solve it with Apple Pencil.")
                    } actions: {
                        Button("Go to Sets", action: showSets)
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        Section("Recent Sets") {
                            ForEach(recentSets) { set in
                                NavigationLink(value: set) {
                                    ProblemSetRow(set: set)
                                }
                            }
                        }
                        Section {
                            Button("All Sets", systemImage: "square.stack.3d.up", action: showSets)
                        }
                    }
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: ProblemSet.self) { set in
                SetDetailView(set: set)
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: ProblemSet.self, inMemory: true)
}
