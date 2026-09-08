import SwiftUI
import SwiftMath

class GhostPillState: ObservableObject {
    @Published var suggestionText: String = ""
    @Published var isThinking: Bool = false
}

/// Renders LaTeX directly to an NSImage using SwiftMath for stable SwiftUI layout sizing
struct MathView: View {
    let latex: String
    let fontSize: CGFloat
    
    init(_ latex: String, fontSize: CGFloat = 16) {
        self.latex = latex
        self.fontSize = fontSize
    }
    
    var body: some View {
        if let image = renderMathImage() {
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundColor(.primary)
        } else {
            Text(latex)
                .font(.system(size: fontSize, design: .monospaced))
        }
    }
    
    private func renderMathImage() -> NSImage? {
        let rawLatex = stripLatexDelimiters(latex)
        guard !rawLatex.isEmpty else { return nil }
        
        let mathImage = MTMathImage(
            latex: rawLatex,
            fontSize: fontSize,
            textColor: .textColor, // Uses dynamic AppKit textColor for light/dark support
            labelMode: .text,      // Inline style
            textAlignment: .left
        )
        
        let (_, image) = mathImage.asImage()
        image?.isTemplate = true
        return image
    }
    
}

/// Three dots that breathe while the language model is working.
///
/// Only the model path ever shows this: deterministic translations appear on the same
/// runloop turn as the keystroke, with no intermediate state to report.
private struct ThinkingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 4, height: 4)
                    .foregroundStyle(.secondary)
                    .opacity(opacity(for: index))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 3
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let distance = abs(phase - Double(index))
        return 0.35 + 0.65 * max(0, 1 - distance)
    }
}

struct GhostPillView: View {
    @ObservedObject var state: GhostPillState

    var body: some View {
        Group {
            if state.suggestionText.isEmpty {
                if state.isThinking {
                    ThinkingDots()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(pill)
                }
            } else {
                HStack(spacing: 9) {
                    MathView(state.suggestionText, fontSize: 15)

                    Text("\u{21E5}")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(pill)
            }
        }
    }

    /// A single quiet surface — no stroke, no shadow, no tint.
    private var pill: some View {
        Capsule().fill(.regularMaterial)
    }
}
