// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Glyph",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Glyph", targets: ["Glyph"])
    ],
    dependencies: [
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Glyph",
            dependencies: [
                .product(name: "LaTeXSwiftUI", package: "LaTeXSwiftUI")
            ],
            path: "Sources/Glyph"
        )
    ]
)
