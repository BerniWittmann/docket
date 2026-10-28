// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Docket",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DocketCore"),
        .executableTarget(name: "Docket", dependencies: ["DocketCore"]),
        .testTarget(
            name: "DocketCoreTests",
            dependencies: ["DocketCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
