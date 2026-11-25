// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XiaomiClipboard",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "xiaomi-clipboard", targets: ["XiaomiClipboard"]),
        .executable(name: "clipboard-tests", targets: ["ClipboardCoreTests"])
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "XiaomiClipboard", dependencies: ["ClipboardCore"]),
        .executableTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"], path: "Tests/ClipboardCoreTests")
    ]
)
