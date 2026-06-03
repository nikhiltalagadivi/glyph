import SwiftUI
import SwiftMath

class GhostPillState: ObservableObject {
    @Published var suggestionText: String = ""
    @Published var isThinking: Bool = false
}

/// Wraps SwiftMath's MTMathUILabel in SwiftUI for live LaTeX preview in the ghost pill
struct MathView: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    
    init(_ latex: String, fontSize: CGFloat = 16) {
        self.latex = latex
        self.fontSize = fontSize
    }
    
    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.fontSize = fontSize
        label.textAlignment = .left
        label.labelMode = .text
        return label
    }
    
    func updateNSView(_ label: MTMathUILabel, context: Context) {
        // Strip delimiters for SwiftMath
        var raw = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("\\(") && raw.hasSuffix("\\)") {
            raw = String(raw.dropFirst(2).dropLast(2))
        } else if raw.hasPrefix("\\[") && raw.hasSuffix("\\]") {
            raw = String(raw.dropFirst(2).dropLast(2))
        } else if raw.hasPrefix("$$") && raw.hasSuffix("$$") && raw.count > 4 {
            raw = String(raw.dropFirst(2).dropLast(2))
        } else if raw.hasPrefix("$") && raw.hasSuffix("$") && raw.count > 2 {
            raw = String(raw.dropFirst().dropLast())
        }
        label.latex = raw.trimmingCharacters(in: .whitespaces)
        label.fontSize = fontSize
        label.textColor = .labelColor
        label.invalidateIntrinsicContentSize()
    }
}

struct GhostPillView: View {
    @ObservedObject var state: GhostPillState

    var body: some View {
        Group {
            if !state.suggestionText.isEmpty {
                HStack(spacing: 6) {
                    Text("⟲")
                        .foregroundColor(.secondary)
                    MathView(state.suggestionText, fontSize: 16)
                        .frame(height: 22)
                        .fixedSize()
                    
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 9, weight: .bold))
                        Text("Tab")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
}
}
