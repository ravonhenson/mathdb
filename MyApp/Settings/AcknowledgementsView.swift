import SwiftUI

/// Third-party license notices for components bundled in the app.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section("KaTeX") {
                Text(Self.license(named: "KaTeX-LICENSE"))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func license(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return text
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
