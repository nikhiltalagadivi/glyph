import SwiftUI
import LaTeXSwiftUI

class GhostPillState: ObservableObject {
    @Published var suggestionText: String = ""
    @Published var isThinking: Bool = false
}

struct GhostPillView: View {
    @ObservedObject var state: GhostPillState

    var body: some View {
        HStack(spacing: 6) {
            if state.isThinking {
                ProgressView()
                    .controlSize(.small)
            } else if !state.suggestionText.isEmpty {
                Text("⟲")
                    .foregroundColor(.secondary)
                LaTeX(state.suggestionText)
                    .foregroundColor(.primary)
                
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}
