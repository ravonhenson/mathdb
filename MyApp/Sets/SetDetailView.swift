import SwiftUI
import SwiftData

/// A set's problems: add, edit, reorder, and delete them, and edit the set itself.
struct SetDetailView: View {
    let set: ProblemSet

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingSet = false
    @State private var isAddingProblem = false
    @State private var problemBeingEdited: Problem?

    var body: some View {
        List {
            Section("Grading") {
                LabeledContent("Answer Matching", value: set.grading.matching.title)
                LabeledContent("Easy / Good",
                               value: "under \(set.grading.easyUnderMinutes) / \(set.grading.goodUnderMinutes) min")
            }

            Section("Problems") {
                if set.problems.isEmpty {
                    Button("Add a Problem", systemImage: "plus") { isAddingProblem = true }
                } else {
                    ForEach(set.orderedProblems) { problem in
                        Button {
                            problemBeingEdited = problem
                        } label: {
                            ProblemRow(problem: problem)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteProblems)
                    .onMove(perform: moveProblems)
                }
            }
        }
        .navigationTitle(set.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Problem", systemImage: "plus") { isAddingProblem = true }
                Button("Set Options", systemImage: "slider.horizontal.3") { isEditingSet = true }
                EditButton()
            }
        }
        .sheet(isPresented: $isEditingSet) {
            SetEditorView(set: set)
        }
        .sheet(isPresented: $isAddingProblem) {
            ProblemEditorView(set: set)
        }
        .sheet(item: $problemBeingEdited) { problem in
            ProblemEditorView(set: set, problem: problem)
        }
    }

    private func deleteProblems(at offsets: IndexSet) {
        let ordered = set.orderedProblems
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        set.updatedAt = .now
    }

    private func moveProblems(from source: IndexSet, to destination: Int) {
        var ordered = set.orderedProblems
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, problem) in ordered.enumerated() {
            problem.sortIndex = index
        }
        set.updatedAt = .now
    }
}

/// A problem's LaTeX source and answer count, used in problem lists.
private struct ProblemRow: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.prompt)
                .font(.body.monospaced())
                .lineLimit(2)
            Text(problem.answers.count == 1 ? "1 accepted answer" : "\(problem.answers.count) accepted answers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
