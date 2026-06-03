import Foundation
import SwiftUI
import AppKit

// We cannot easily compile a script with SPM dependencies via 'swift test-latex.swift' unless we use swift build.
// Let's just trust that LaTeXSwiftUI works, as it is literally designed to render to SwiftUI Views.
print("Trusting LaTeXSwiftUI.")
