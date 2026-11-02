import Foundation

/// Keys and defaults for app-wide settings stored in `UserDefaults` (via `@AppStorage`).
/// Grading is configured per problem set (see `GradingSettings`), not here.
nonisolated enum AppSettings {
    enum Key {
        static let handwritingRetention = "handwritingRetention"
    }

    enum Default {
        static let handwritingRetention = HandwritingRetention.all
    }
}

/// How long the handwriting from graded attempts is kept. Time, grade, and the
/// recognized answer are always kept; this only controls the ink.
nonisolated enum HandwritingRetention: String, CaseIterable, Identifiable {
    case all
    case latestOnly
    case none

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Attempts"
        case .latestOnly: "Latest Attempt Only"
        case .none: "Don't Keep After Grading"
        }
    }
}

/// How a recognized answer is compared with an accepted answer.
nonisolated enum AnswerMatching: String, CaseIterable, Identifiable, Codable {
    /// Same LaTeX after normalizing whitespace and formatting.
    case exact
    /// Mathematically equal, e.g. `\frac{1}{2}` and `0.5`.
    case equivalent
    /// Numerically within a tolerance.
    case tolerance

    var id: Self { self }

    var title: String {
        switch self {
        case .exact: "Exact"
        case .equivalent: "Equivalent"
        case .tolerance: "Within Tolerance"
        }
    }
}
