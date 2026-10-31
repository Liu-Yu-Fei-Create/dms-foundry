// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DMSFoundry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DMSFoundry", targets: ["DMSFoundry"]),
        .library(name: "DMSEngine", targets: ["DMSEngine"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "DMSEngine", resources: [.copy("Resources")]),
        .executableTarget(name: "DMSFoundry", dependencies: ["DMSEngine"], resources: [.copy("Resources")]),
        .testTarget(name: "DMSEngineTests", dependencies: ["DMSEngine"]),
    ],
    swiftLanguageVersions: [.v5]
)
