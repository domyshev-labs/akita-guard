// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AkitaGuardCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AkitaGuardCore", targets: ["AkitaGuardCore"])],
    targets: [
        .target(name: "AkitaGuardCore", path: "Core"),
        .testTarget(name: "AkitaGuardCoreTests", dependencies: ["AkitaGuardCore"], path: "Tests")
    ]
)
