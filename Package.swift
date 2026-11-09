// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Weeklet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Weeklet", targets: ["Weeklet"]),
        .library(name: "WeekletCore", targets: ["WeekletCore"])
    ],
    targets: [
        .target(name: "WeekletCore"),
        .executableTarget(name: "Weeklet", dependencies: ["WeekletCore"]),
        .testTarget(name: "WeekletCoreTests", dependencies: ["WeekletCore"])
    ],
    swiftLanguageModes: [.v6]
)
