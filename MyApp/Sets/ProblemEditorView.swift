import SwiftUI
import SwiftData

/// Creates or edits a problem: its LaTeX prompt and accepted answers.
///
/// Every field is rendered with KaTeX as you type, and Save stays disabled until
/// the prompt and all answers are valid LaTeX.
struct ProblemEditorView: View {
    let set: ProblemSet
    /// The problem to edit, or `nil` to add a new one to `set`.
    let problem: Problem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var prompt: String
    @State private var answers: [AcceptedAnswer]
    /// Whether each field last rendered as valid LaTeX; `nil` while it hasn't rendered yet.
    @State private var validity: [String: Bool] = [:]

    private static let promptKey = "prompt"

    init(set: ProblemSet, problem: Problem? = nil) {
        self.set = set
        self.problem = problem
        _prompt = State(initialValue: problem?.prompt ?? "")
        _answers = State(initialValue: problem?.answers ?? [AcceptedAnswer(latex: "")])
    }

    private var canSave: Bool {
        !trimmed(prompt).isEmpty && validity[Self.promptKey] == true
            && !answers.isEmpty
            && answers.allSatisfy { !trimmed($0.latex).isEmpty && validity[$0.id.uuidString] == true }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LaTeXField("Problem LaTeX", writingTitle: "Write Problem", text: $prompt)
                        .onChange(of: prompt) { validity[Self.promptKey] = nil }
                    if !trimmed(prompt).isEmpty {
                        LaTeXView(latex: prompt) { validity[Self.promptKey] = $0 }
                    }
                } header: {
                    Text("Problem")
                } footer: {
                    if validity[Self.promptKey] == false {
                        Text("This isn't valid LaTeX yet.").foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach($answers) { $answer in
                        AnswerEditorRow(answer: $answer, defaultMatching: set.grading.matching,
                                        isValid: validity[answer.id.uuidString]) { ok in
                            validity[answer.id.uuidString] = ok
                        }
                        .onChange(of: answer.latex) { validity[answer.id.uuidString] = nil }
                    }
                    .onDelete { answers.remove(atOffsets: $0) }

                    Button("Add Answer", systemImage: "plus") {
                        answers.append(AcceptedAnswer(latex: ""))
                    }
                } header: {
                    Text("Accepted Answers")
                } footer: {
                    Text("An answer is correct if it matches any of these.")
                }
            }
            .navigationTitle(problem == nil ? "New Problem" : "Edit Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let cleanedAnswers = answers.map { answer in
            var answer = answer
            answer.latex = trimmed(answer.latex)
            return answer
        }
        if let problem {
            problem.prompt = trimmed(prompt)
            problem.answers = cleanedAnswers
            problem.updatedAt = .now
        } else {
            let nextIndex = (set.problems.map(\.sortIndex).max() ?? -1) + 1
            let newProblem = Problem(prompt: trimmed(prompt), answers: cleanedAnswers, sortIndex: nextIndex)
            modelContext.insert(newProblem)
            set.problems.append(newProblem)
        }
        set.updatedAt = .now
        dismiss()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One accepted answer: its LaTeX, a rendered preview, and its matching rule.
private struct AnswerEditorRow: View {
    @Binding var answer: AcceptedAnswer
    let defaultMatching: AnswerMatching
    let isValid: Bool?
    let onRendered: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LaTeXField("Answer LaTeX", writingTitle: "Write Answer", text: $answer.latex)
            if !answer.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LaTeXView(latex: answer.latex, maxHeight: 120, onRendered: onRendered)
                if isValid == false {
                    Text("This isn't valid LaTeX yet.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Picker("Matching", selection: $answer.matching) {
                Text("Set Default (\(defaultMatching.title))").tag(AnswerMatching?.none)
                ForEach(AnswerMatching.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A monospaced, multi-line text field for LaTeX source, with a button to write it
/// with Apple Pencil instead of typing.
private struct LaTeXField: View {
    let title: String
    /// Title of the handwriting sheet.
    let writingTitle: String
    @Binding var text: String

    @State private var isWriting = false

    init(_ title: String, writingTitle: String, text: Binding<String>) {
        self.title = title
        self.writingTitle = writingTitle
        _text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TextField(title, text: $text, axis: .vertical)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Write with Apple Pencil", systemImage: "pencil.and.scribble") {
                isWriting = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)  // keeps taps on the row from triggering it
        }
        .sheet(isPresented: $isWriting) {
            HandwritingLaTeXSheet(title: writingTitle, text: $text)
        }
    }
}
