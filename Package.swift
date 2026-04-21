// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "synergy-gesture-bridge",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "SynergyGestureBridge",
            path: "Sources/SynergyGestureBridge"
        )
    ]
)
