import SwiftUI
import SwiftData

/// All problem sets: create, open, and delete.
struct SetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProblemSet.updatedAt, order: .reverse) private var sets: [ProblemSet]

    @State private var isCreatingSet = false
    @State private var setPendingDeletion: ProblemSet?

    var body: some View {
        NavigationStack {
            Group {
                if sets.isEmpty {
                    ContentUnavailableView {
                        Label("No Problem Sets", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Create a set to get started.")
                    } actions: {
                        Button("New Set") { isCreatingSet = true }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        ForEach(sets) { set in
                            NavigationLink(value: set) {
                                ProblemSetRow(set: set)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    setPendingDeletion = set
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sets")
            .navigationDestination(for: ProblemSet.self) { set in
                SetDetailView(set: set)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Set", systemImage: "plus") { isCreatingSet = true }
                }
            }
            .sheet(isPresented: $isCreatingSet) {
                SetEditorView()
            }
            .confirmationDialog(
                "Delete \u{201C}\(setPendingDeletion?.title ?? "")\u{201D}?",
                isPresented: Binding(
                    get: { setPendingDeletion != nil },
                    set: { if !$0 { setPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Set", role: .destructive) {
                    if let setPendingDeletion {
                        modelContext.delete(setPendingDeletion)
                    }
                    setPendingDeletion = nil
                }
            } message: {
                Text("This deletes the set and all of its problems. This can't be undone.")
            }
        }
    }
}

/// A set's title and problem count, used in set lists.
struct ProblemSetRow: View {
    let set: ProblemSet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.title)
                .font(.headline)
            Text(set.problems.count == 1 ? "1 problem" : "\(set.problems.count) problems")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SetsView()
        .modelContainer(for: ProblemSet.self, inMemory: true)
}
