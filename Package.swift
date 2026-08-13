// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Owl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "OwlServer", path: "Sources/OwlServer"),
        .executableTarget(name: "owl-hook", path: "Sources/owl-hook"),
        .executableTarget(name: "OwlApp", path: "Sources/OwlApp"),
    ]
)
