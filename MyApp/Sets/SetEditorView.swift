import SwiftUI
import SwiftData

/// Creates a new set, or edits an existing set's title and grading.
struct SetEditorView: View {
    /// The set to edit, or `nil` to create a new one.
    let set: ProblemSet?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var grading: GradingSettings

    init(set: ProblemSet? = nil) {
        self.set = set
        _title = State(initialValue: set?.title ?? "")
        _grading = State(initialValue: set?.grading ?? .default)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                GradingSettingsSection(grading: $grading)
            }
            .navigationTitle(set == nil ? "New Set" : "Set Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let set {
            set.title = trimmedTitle
            set.grading = grading
            set.updatedAt = .now
        } else {
            modelContext.insert(ProblemSet(title: trimmedTitle, grading: grading))
        }
        dismiss()
    }
}

/// The per-set grading options: answer matching and time thresholds.
struct GradingSettingsSection: View {
    @Binding var grading: GradingSettings

    var body: some View {
        Section {
            Picker("Answer Matching", selection: $grading.matching) {
                ForEach(AnswerMatching.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            if grading.matching == .tolerance {
                LabeledContent("Tolerance") {
                    TextField("Tolerance", value: $grading.tolerance, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Answers")
        } footer: {
            Text("The default for this set. Each accepted answer can choose its own.")
        }

        Section {
            // Easy must stay below Good; the ranges keep them ordered (and valid).
            Stepper("Easy: under \(grading.easyUnderMinutes) min", value: $grading.easyUnderMinutes,
                    in: 1...max(1, grading.goodUnderMinutes - 1))
            Stepper("Good: under \(grading.goodUnderMinutes) min", value: $grading.goodUnderMinutes,
                    in: min(grading.easyUnderMinutes + 1, 240)...240)
            Stepper("Pause after \(grading.idleTimeoutMinutes) min idle", value: $grading.idleTimeoutMinutes,
                    in: 1...30)
        } header: {
            Text("Grading")
        } footer: {
            Text("A correct answer is graded by time spent on the problem; slower than Good is Hard. A wrong answer is Again. The timer pauses when there's no Apple Pencil activity.")
        }
    }
}

#Preview {
    SetEditorView()
        .modelContainer(for: ProblemSet.self, inMemory: true)
}
