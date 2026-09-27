// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UsageMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "UsageMeterCore"
        ),
        .executableTarget(
            name: "UsageMeter",
            dependencies: ["UsageMeterCore"]
        ),
        .testTarget(
            name: "UsageMeterCoreTests",
            dependencies: ["UsageMeterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
