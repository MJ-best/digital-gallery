// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DigitalGalleryApple",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "GalleryBridge", targets: ["GalleryBridge"]),
        .executable(name: "DigitalGalleryApp", targets: ["DigitalGalleryApp"]),
    ],
    targets: [
        .binaryTarget(
            name: "GalleryFFI",
            path: "Libs/GalleryFFI.xcframework"
        ),
        .target(
            name: "GalleryBridge",
            dependencies: ["GalleryFFI"],
            path: "Sources/GalleryBridge"
        ),
        .executableTarget(
            name: "DigitalGalleryApp",
            dependencies: ["GalleryBridge"],
            path: "Sources/DigitalGalleryApp"
        ),
        .testTarget(
            name: "GalleryBridgeTests",
            dependencies: ["GalleryBridge"],
            path: "Tests/GalleryBridgeTests"
        ),
    ]
)
