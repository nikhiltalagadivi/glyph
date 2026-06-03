import AppKit
import SwiftUI
import LaTeXSwiftUI

let markdown = #"$\int_{0}^{\pi} x^2 \, dx$"#

@MainActor
func test() {
    let view = LaTeX(markdown).font(.system(size: 20)).foregroundColor(.black).fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    if let img = renderer.nsImage {
        let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let data = bitmapRep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: "/Users/nikhiltalagadivi/Documents/TabNote/test/test_out5.png"))
        print("Saved to test_out5.png")
    }
    exit(0)
}

DispatchQueue.main.async {
    test()
}

RunLoop.main.run()
