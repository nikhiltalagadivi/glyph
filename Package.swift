// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TabNote",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "TabNote", targets: ["TabNote"])
    ],
    dependencies: [
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "TabNote",
            dependencies: [
                .product(name: "LaTeXSwiftUI", package: "LaTeXSwiftUI")
            ],
            path: "Sources/TabNote"
        )
    ]
)
