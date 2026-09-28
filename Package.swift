// swift-tools-version: 5.9
import PackageDescription

#if os(Linux)
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
    .package(url: "https://github.com/vapor/websocket-kit.git", exact: "2.16.2"),
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0")
]
let crypto: [Target.Dependency] = [.product(name: "Crypto", package: "swift-crypto")]
let transport: [Target.Dependency] = [.product(name: "WebSocketKit", package: "websocket-kit"), .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio")]
let desktopFiles = ["main.swift", "Views.swift", "QQView.swift", "QQArtworkSettingsView.swift", "BotEngine.swift", "WeChatBridge.swift"]
#else
let dependencies: [Package.Dependency] = []
let crypto: [Target.Dependency] = []
let transport: [Target.Dependency] = []
let desktopFiles = ["LinuxMain.swift", "LinuxSupport.swift"]
#endif

let package = Package(
    name: "WeChatAIBot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WeChatAIBot", targets: ["WeChatAIBot"])],
    dependencies: dependencies,
    targets: [
        .target(name: "BotCore", dependencies: crypto),
        .executableTarget(name: "WeChatAIBot", dependencies: [.target(name: "BotCore")] + crypto + transport, exclude: desktopFiles),
        .testTarget(name: "BotCoreTests", dependencies: ["BotCore"]),
        .testTarget(name: "QQEngineTests", dependencies: ["WeChatAIBot"], exclude: ["onebot_fixture.py", "synthetic-images.json"])
    ]
)
