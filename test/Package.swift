// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TestLatex",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "TestLatex",
            dependencies: [
                .product(name: "LaTeXSwiftUI", package: "LaTeXSwiftUI")
            ]
        )
    ]
)
