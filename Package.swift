// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Glyph",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Glyph", targets: ["Glyph"]),
        .library(name: "GlyphMath", targets: ["GlyphMath"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.0")
    ],
    targets: [
        // Pure-Foundation math engine: tokenizer, parser, LaTeX renderer, scope scanner.
        // Kept free of AppKit/SwiftUI so it stays fast to build and testable headlessly.
        .target(
            name: "GlyphMath",
            path: "Sources/GlyphMath"
        ),
        .executableTarget(
            name: "Glyph",
            dependencies: [
                "GlyphMath",
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Sources/Glyph"
        ),
        // Shared corpus so the translation tests and the render tests exercise
        // exactly the same phrases.
        .target(
            name: "GlyphTestSupport",
            dependencies: ["GlyphMath"],
            path: "Tests/GlyphTestSupport"
        ),
        .testTarget(
            name: "GlyphMathTests",
            dependencies: ["GlyphMath", "GlyphTestSupport"],
            path: "Tests/GlyphMathTests"
        ),
        // Verifies that every LaTeX string the translator emits actually parses in
        // the renderer the app ships with — a silent render failure would otherwise
        // just look like "the suggestion never appeared".
        .testTarget(
            name: "GlyphRenderTests",
            dependencies: [
                "GlyphMath",
                "GlyphTestSupport",
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Tests/GlyphRenderTests"
        )
    ]
)
