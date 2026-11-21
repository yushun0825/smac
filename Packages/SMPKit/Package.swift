// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMPKit",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SMPKit", targets: ["SMPKit"]),
        .executable(name: "smprender", targets: ["smprender"]),
    ],
    targets: [
        .target(name: "SMPKit"),
        .executableTarget(name: "smprender", dependencies: ["SMPKit"]),
        .testTarget(
            name: "SMPKitTests",
            dependencies: ["SMPKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
