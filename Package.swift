// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Owl",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "OwlShared", path: "Sources/OwlShared"),
        .executableTarget(name: "OwlServer", path: "Sources/OwlServer"),
        .executableTarget(name: "owl-hook", dependencies: ["OwlShared"], path: "Sources/owl-hook"),
        .executableTarget(name: "OwlApp", dependencies: ["OwlShared"], path: "Sources/OwlApp"),
    ]
)
