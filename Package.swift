// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Skreener",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // The frame, background and pixel helpers, without AppKit, for the app and the iOS Share Extension (#396).
        .library(name: "SkreenerCore", targets: ["SkreenerCore"]),
        .executable(name: "Skreener", targets: ["Skreener"]),
    ],
    targets: [
        .target(name: "SkreenerCore", path: "Sources/SkreenerCore"),
        .executableTarget(name: "Skreener", dependencies: ["SkreenerCore"], path: "Sources/Skreener"),
        // SkreenerCore too, for the pixel-identity tests that compare it with the AppKit drawing it replaced.
        .testTarget(name: "SkreenerTests", dependencies: ["Skreener", "SkreenerCore"], path: "Tests/SkreenerTests"),
        .testTarget(name: "SkreenerCoreTests", dependencies: ["SkreenerCore"], path: "Tests/SkreenerCoreTests"),
    ]
)
