import Foundation
import SwiftData

/// A named collection of problems with its own grading settings.
@Model
final class ProblemSet {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var grading: GradingSettings

    @Relationship(deleteRule: .cascade, inverse: \Problem.set)
    var problems: [Problem] = []

    init(title: String, grading: GradingSettings = .default) {
        id = UUID()
        self.title = title
        createdAt = .now
        updatedAt = .now
        self.grading = grading
    }

    /// Problems in the order the user arranged them. (Relationships don't keep order.)
    var orderedProblems: [Problem] {
        problems.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// A single problem: a LaTeX prompt and the answers that count as correct.
@Model
final class Problem {
    @Attribute(.unique) var id: UUID
    var set: ProblemSet?
    var sortIndex: Int
    /// The problem statement, as valid LaTeX.
    var prompt: String
    /// The answer is correct if it matches any of these.
    var answers: [AcceptedAnswer]
    var createdAt: Date
    var updatedAt: Date

    init(prompt: String, answers: [AcceptedAnswer], sortIndex: Int) {
        id = UUID()
        self.prompt = prompt
        self.answers = answers
        self.sortIndex = sortIndex
        createdAt = .now
        updatedAt = .now
    }
}

/// One answer that counts as correct, and how to compare against it.
nonisolated struct AcceptedAnswer: Codable, Hashable, Identifiable {
    var id = UUID()
    var latex: String
    /// `nil` uses the set's default matching.
    var matching: AnswerMatching?
}

/// How a set checks answers and turns time into a grade.
nonisolated struct GradingSettings: Codable, Hashable {
    /// Default comparison for answers that don't choose their own.
    var matching: AnswerMatching
    /// Allowed difference when matching is `.tolerance`.
    var tolerance: Double
    /// A correct answer under this many minutes is Easy.
    var easyUnderMinutes: Int
    /// A correct answer under this many minutes is Good; slower is Hard.
    var goodUnderMinutes: Int
    /// The timer pauses after this many minutes without Apple Pencil activity.
    var idleTimeoutMinutes: Int

    static let `default` = GradingSettings(
        matching: .equivalent,
        tolerance: 0.001,
        easyUnderMinutes: 2,
        goodUnderMinutes: 5,
        idleTimeoutMinutes: 3
    )
}
