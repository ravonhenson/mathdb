import CoreML
import Foundation

/// Turns the model's per-step token scores into a LaTeX string.
///
/// Mirrors `greedy_decode()` in `ml/model.py` and `Tokenizer.decode()` in `ml/tokenizer.py`.
nonisolated struct CTCDecoder {
    /// Token strings; the index is the token id. Id 0 is the CTC blank.
    let vocabulary: [String]
    let blankID = 0

    init(vocabulary: [String]) {
        self.vocabulary = vocabulary
    }

    init(contentsOf url: URL) throws {
        self.init(vocabulary: try JSONDecoder().decode([String].self, from: Data(contentsOf: url)))
    }

    /// Decodes log-probabilities shaped `[1, steps, vocabulary]`.
    func decode(_ logProbs: MLShapedArray<Float>) -> String {
        latex(from: greedyIDs(logProbs))
    }

    /// Best token per step, then merge repeats and remove blanks.
    /// e.g. steps "x x _ ^ ^ _ 2" -> "x ^ 2"
    func greedyIDs(_ logProbs: MLShapedArray<Float>) -> [Int] {
        let steps = logProbs.shape[1]
        let width = logProbs.shape[2]
        let scalars = logProbs.scalars

        var ids: [Int] = []
        var previous: Int?
        for step in 0..<steps {
            let row = scalars[(step * width)..<((step + 1) * width)]
            let best = row.indices.max { row[$0] < row[$1] }.map { $0 - row.startIndex } ?? blankID
            if best != previous && best != blankID {
                ids.append(best)
            }
            previous = best
        }
        return ids
    }

    /// Joins tokens into LaTeX, adding a space only where LaTeX needs one
    /// ("\alpha x", not "\alphax") and after the row break "\\".
    func latex(from ids: [Int]) -> String {
        var output = ""
        var previous = ""
        for id in ids where id != blankID && vocabulary.indices.contains(id) {
            let token = vocabulary[id]
            if previous == "\\\\" || (Self.isCommand(previous) && token.first?.isLetter == true) {
                output += " "
            }
            output += token
            previous = token
        }
        return output
    }

    /// True for a backslash followed by one or more ASCII letters, like `\frac`.
    private static func isCommand(_ token: String) -> Bool {
        token.count > 1 && token.first == "\\"
            && token.dropFirst().allSatisfy { $0.isASCII && $0.isLetter }
    }
}
