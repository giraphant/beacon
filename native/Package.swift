// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BeaconCore", swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]),
        .executableTarget(name: "Beacon", dependencies: ["BeaconCore"]),
        .testTarget(name: "BeaconCoreTests", dependencies: ["BeaconCore"]),
        .testTarget(name: "BeaconAppTests", dependencies: ["Beacon"]),
    ]
)
