import SwiftUI
import WebKit

/// Renders LaTeX as typeset math using the bundled KaTeX page (`katex.html`,
/// built by `tools/build_katex_html.py`). Works offline.
///
/// The view sizes its height to the rendered math (up to `maxHeight`) and scrolls
/// horizontally when an expression is wider than the available space.
struct LaTeXView: View {
    let latex: String
    var maxHeight: CGFloat = 240
    /// Called after each render with `true` if KaTeX could parse the input.
    var onRendered: (Bool) -> Void = { _ in }

    @State private var page = WebPage()
    @State private var isLoaded = false
    @State private var contentHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 26

    var body: some View {
        WebView(page)
            .webViewContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maxHeight))
            .task(id: "\(fontSize)|\(latex)") {
                await render()
            }
    }

    private func render() async {
        if !isLoaded {
            guard let url = Bundle.main.url(forResource: "katex", withExtension: "html"),
                  let html = try? String(contentsOf: url, encoding: .utf8) else {
                onRendered(false)
                return
            }
            do {
                for try await _ in page.load(html: html) {}
            } catch {
                onRendered(false)
                return
            }
            isLoaded = true
        }

        // `render` is defined in katex.html and returns { ok, message, width, height }.
        let result = try? await page.callJavaScript(
            "return await render(latex, fontSize)",
            arguments: ["latex": latex, "fontSize": Double(fontSize)]
        )
        guard let info = result as? [String: Any] else {
            onRendered(false)
            return
        }
        if let height = info["height"] as? Double, height > 0 {
            contentHeight = height
        }
        onRendered(info["ok"] as? Bool ?? false)
    }
}

#Preview {
    LaTeXView(latex: #"\frac{d^{2}x}{dt^{2}}=-\omega^{2}x"#)
        .padding()
}
