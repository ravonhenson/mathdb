import Foundation
import PencilKit

/// Saves the current handwriting and its result to a file on this device, so they
/// survive the app being closed. Nothing is sent anywhere.
struct DrawingStore {
    struct Snapshot {
        var drawing: PKDrawing
        var latex: String
    }

    /// The on-disk format: the drawing's own data representation plus the LaTeX.
    private struct Saved: Codable {
        var drawing: Data
        var latex: String
    }

    let fileURL: URL

    init(fileURL: URL = .applicationSupportDirectory.appending(path: "MathInput/current.plist")) {
        self.fileURL = fileURL
    }

    /// Returns the saved snapshot, or `nil` if there's none or it can't be read.
    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? PropertyListDecoder().decode(Saved.self, from: data),
              let drawing = try? PKDrawing(data: saved.drawing) else {
            return nil
        }
        return Snapshot(drawing: drawing, latex: saved.latex)
    }

    func save(_ snapshot: Snapshot) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Saved(drawing: snapshot.drawing.dataRepresentation(), latex: snapshot.latex))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
