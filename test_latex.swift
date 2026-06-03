import AppKit
import SwiftUI
import LaTeXSwiftUI

@MainActor
func test() {
    let markdown = #"\( \int_{0}^{\pi} x^2 \, dx \)"#
    let processed = markdown
    
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(.black)
        .fixedSize()

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    let img = renderer.nsImage
    
    print("Image: \(String(describing: img))")
    if let img = img {
        print("Size: \(img.size)")
    }
}
test()
