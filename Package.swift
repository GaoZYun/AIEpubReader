// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIReader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIReader", targets: ["AIReader"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AIReader",
            dependencies: [],
            path: ".",
            exclude: ["README.md"],
            sources: [
                "AIReaderApp.swift",
                "ContentView.swift",
                "Models",
                "Services",
                "Views"
            ],
            resources: [
                .process("AIReader.entitlements")
            ]
        )
    ]
)
