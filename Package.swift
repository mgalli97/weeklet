// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Weeklet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Weeklet", targets: ["Weeklet"]),
        .executable(name: "WeekletInstaller", targets: ["WeekletInstaller"]),
        .executable(name: "WeekletRelease", targets: ["WeekletRelease"]),
        .library(name: "WeekletCore", targets: ["WeekletCore"])
    ],
    targets: [
        .target(name: "WeekletCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Weeklet", dependencies: ["WeekletCore"], resources: [.process("Assets")]),
        .executableTarget(name: "WeekletInstaller", dependencies: ["WeekletCore"]),
        .executableTarget(name: "WeekletRelease", dependencies: ["WeekletCore"]),
        .testTarget(name: "WeekletCoreTests", dependencies: ["WeekletCore"])
    ],
    swiftLanguageModes: [.v6]
)
