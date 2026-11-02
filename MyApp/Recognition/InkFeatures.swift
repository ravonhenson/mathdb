import Foundation
import PencilKit

/// Turns ink into the per-point features the model was trained on.
///
/// This is a line-for-line port of `ink_to_features()` in `ml/inkml.py`. The model only
/// understands numbers produced exactly this way, so any change here must be mirrored in
/// Python (and the golden fixtures regenerated with `ml/make_fixtures.py`).
nonisolated enum InkFeatures {
    /// Features per point: `[dx, dy, y, pen_start]`.
    static let featureCount = 4

    /// Extracts each stroke's points, in drawing order, in canvas coordinates.
    static func strokes(from drawing: PKDrawing) -> [[SIMD2<Float>]] {
        drawing.strokes.map { stroke in
            stroke.path.map { point in
                let location = point.location.applying(stroke.transform)
                return SIMD2(Float(location.x), Float(location.y))
            }
        }
    }

    /// Converts strokes into one sequence of `[dx, dy, y, pen_start]` rows.
    static func features(from strokes: [[SIMD2<Float>]]) -> [SIMD4<Float>] {
        // Drop points where the pen didn't move, then drop strokes left empty.
        let cleaned: [[SIMD2<Float>]] = strokes.compactMap { stroke in
            let kept = stroke.indices.filter { $0 == 0 || stroke[$0] != stroke[$0 - 1] }.map { stroke[$0] }
            return kept.isEmpty ? nil : kept
        }
        guard let first = cleaned.first?.first else { return [] }

        // Shift so the top-left of the ink is (0, 0), then divide by the ink height so
        // large and small handwriting look the same. Height is floored at 1, as in Python.
        let points = cleaned.flatMap { $0 }
        let minimum = points.reduce(first) { pointwiseMin($0, $1) }
        let shifted = points.map { $0 - minimum }
        let height = max(shifted.map(\.y).max() ?? 0, 1)
        let normalized = shifted.map { $0 / height }

        var penStarts = Set<Int>()
        var index = 0
        for stroke in cleaned {
            penStarts.insert(index)
            index += stroke.count
        }

        // Deltas run across stroke boundaries (the pen-up jump is included); the first is 0.
        return normalized.indices.map { i in
            let delta = i == 0 ? .zero : normalized[i] - normalized[i - 1]
            return SIMD4(delta.x, delta.y, normalized[i].y, penStarts.contains(i) ? 1 : 0)
        }
    }
}
