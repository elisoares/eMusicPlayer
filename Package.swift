// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "eMusicPlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "eMusicPlayer", path: "Sources/eMusicPlayer")
    ]
)
