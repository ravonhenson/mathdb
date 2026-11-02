import SwiftUI
import UIKit

/// The floating tray over the canvas: rendered math, the Recognize button, and a
/// collapsible section with the raw LaTeX source.
///
/// It spans the full window width in every size class, because typeset math is
/// wide; when the window resizes (folding, Split View) only its width changes.
struct ResultPanel: View {
    let latex: String
    let errorMessage: String?
    let isRecognizing: Bool
    let canRecognize: Bool
    let recognize: () -> Void

    @State private var showsSource = false
    @State private var renderFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                result
                    .frame(maxWidth: .infinity, minHeight: 44)

                Button("Recognize", systemImage: "wand.and.sparkles", action: recognize)
                    .opacity(isRecognizing ? 0 : 1)
                    .overlay {
                        if isRecognizing {
                            ProgressView()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canRecognize || isRecognizing)
            }

            if !latex.isEmpty && errorMessage == nil {
                sourceDisclosure
            }
        }
        .padding()
        // Corners follow the screen's corners when the tray sits near them.
        .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 20), isUniform: true))
    }

    @ViewBuilder
    private var result: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Keep the web view alive while empty so KaTeX loads only once.
            ZStack {
                LaTeXView(latex: latex) { ok in
                    renderFailed = !ok
                    // Show the source right away when the model's output isn't valid LaTeX.
                    if !ok && !latex.isEmpty {
                        showsSource = true
                    }
                }
                .opacity(latex.isEmpty ? 0 : 1)
                .accessibilityHidden(latex.isEmpty)

                if latex.isEmpty {
                    Text("Write an expression, then tap Recognize.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sourceDisclosure: some View {
        DisclosureGroup(isExpanded: $showsSource) {
            HStack(alignment: .firstTextBaseline) {
                Text(latex)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy LaTeX", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = latex
                }
                .labelStyle(.iconOnly)
            }
            .padding(.top, 4)
        } label: {
            Label(renderFailed ? "LaTeX source (couldn't render)" : "LaTeX source",
                  systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.subheadline)
                .foregroundStyle(renderFailed ? .red : .secondary)
        }
    }
}

#Preview {
    ResultPanel(latex: #"\int_{E}f(x)\mu(dx)"#, errorMessage: nil,
                isRecognizing: false, canRecognize: true, recognize: {})
}
