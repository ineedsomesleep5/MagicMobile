// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MagicMobileOnDevice",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MagicMobileOnDevice", targets: ["MagicMobileOnDevice"])],
    targets: [
        .target(name: "CMagicEngine", publicHeadersPath: "include"),
        .target(name: "MagicMobileOnDevice", dependencies: ["CMagicEngine"]),
        .testTarget(name: "MagicMobileOnDeviceTests", dependencies: ["MagicMobileOnDevice"])
    ]
)
