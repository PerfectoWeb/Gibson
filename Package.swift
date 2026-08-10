// swift-tools-version: 5.9

// This manifest exists so editors with SourceKit-LSP (Xcode, VS Code, Zed)
// can index the sources. The shippable .saver bundle is produced by the
// Makefile, which links against ScreenSaver.framework and builds universal.

import PackageDescription

let package = Package(
    name: "Gibson",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Gibson", type: .dynamic, targets: ["Gibson"])
    ],
    targets: [
        .target(
            name: "Gibson",
            path: "Sources/Gibson",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
