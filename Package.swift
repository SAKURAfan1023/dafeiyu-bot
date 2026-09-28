// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeChatAIBot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WeChatAIBot", targets: ["WeChatAIBot"])],
    targets: [
        .target(name: "BotCore"),
        .executableTarget(name: "WeChatAIBot", dependencies: ["BotCore"]),
        .testTarget(name: "BotCoreTests", dependencies: ["BotCore"]),
        .testTarget(name: "QQEngineTests", dependencies: ["WeChatAIBot"], exclude: ["onebot_fixture.py"])
    ]
)
