// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FXTalk",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FXTalk", targets: ["FXTalk"])],
    targets: [
        .target(name: "FXTalkCore"),
        .executableTarget(name: "FXTalk", dependencies: ["FXTalkCore"]),
        .testTarget(name: "FXTalkCoreTests", dependencies: ["FXTalkCore"])
    ]
)
