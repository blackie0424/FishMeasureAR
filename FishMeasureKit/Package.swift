// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FishMeasureKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FishMeasureKit", targets: ["FishMeasureKit"])
    ],
    targets: [
        .target(name: "FishMeasureKit"),
        .testTarget(name: "FishMeasureKitTests", dependencies: ["FishMeasureKit"]),
    ]
)
