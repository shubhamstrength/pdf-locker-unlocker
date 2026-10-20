// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDFLocker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PDFLocker", targets: ["PDFLocker"]),
        .library(name: "PDFLockerCore", targets: ["PDFLockerCore"]),
    ],
    targets: [
        .target(name: "PDFLockerCore"),
        .executableTarget(name: "PDFLocker", dependencies: ["PDFLockerCore"]),
        .testTarget(name: "PDFLockerCoreTests", dependencies: ["PDFLockerCore"]),
    ]
)
