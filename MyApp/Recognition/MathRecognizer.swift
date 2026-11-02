import CoreML
import Foundation

/// Runs the bundled Core ML model (exported by `ml/export_coreml.py`) off the main actor.
actor MathRecognizer {
    enum RecognizerError: LocalizedError {
        case missingResource(String)
        case tooManyPoints(Int)
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                "\(name) is missing from the app bundle. Run ml/export_coreml.py."
            case .tooManyPoints(let count):
                "This ink has \(count) points; the model handles at most \(MathRecognizer.maxPoints). Try a shorter expression."
            case .unexpectedOutput:
                "The model returned output in an unexpected format."
            }
        }
    }

    /// The longest ink the model saw in training (`train --max-points`).
    static let maxPoints = 2048

    private let model: MLModel
    private let decoder: CTCDecoder

    init() async throws {
        guard let modelURL = Bundle.main.url(forResource: "MathCTC", withExtension: "mlmodelc") else {
            throw RecognizerError.missingResource("MathCTC.mlpackage")
        }
        guard let vocabularyURL = Bundle.main.url(forResource: "vocab", withExtension: "json") else {
            throw RecognizerError.missingResource("vocab.json")
        }
        model = try await MLModel.load(contentsOf: modelURL, configuration: MLModelConfiguration())
        decoder = try CTCDecoder(contentsOf: vocabularyURL)
    }

    @MainActor private static var sharedLoad: Task<MathRecognizer, any Error>?

    /// The app-wide recognizer. The model loads on first use and is shared after that.
    @MainActor static func shared() async throws -> MathRecognizer {
        if let sharedLoad {
            return try await sharedLoad.value
        }
        let load = Task { try await MathRecognizer() }
        sharedLoad = load
        do {
            return try await load.value
        } catch {
            sharedLoad = nil  // allow a retry next time
            throw error
        }
    }

    /// Recognizes strokes (from `InkFeatures.strokes(from:)`) and returns LaTeX.
    func recognize(_ strokes: [[SIMD2<Float>]]) async throws -> String {
        let features = InkFeatures.features(from: strokes)
        guard !features.isEmpty else { return "" }
        guard features.count <= Self.maxPoints else {
            throw RecognizerError.tooManyPoints(features.count)
        }

        let scalars = features.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        let ink = MLShapedArray<Float>(scalars: scalars, shape: [1, features.count, InkFeatures.featureCount])
        let input = try MLDictionaryFeatureProvider(dictionary: ["ink": MLMultiArray(ink)])

        let output = try await model.prediction(from: input)
        guard let logProbs = output.featureValue(for: "log_probs")?.multiArrayValue else {
            throw RecognizerError.unexpectedOutput
        }
        return decoder.decode(MLShapedArray<Float>(converting: logProbs))
    }
}
