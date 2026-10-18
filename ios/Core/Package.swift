// swift-tools-version:5.9
//
// 可移植核心层：不含任何 SwiftUI / UIKit / Combine 依赖。
// 之所以单独成包，是因为这台开发机是 Windows —— 排版、SSE 解析、Prompt 拼装、
// 批改 JSON 解析这些纯逻辑可以用 Windows 版 Swift 工具链直接 `swift test`，
// 把错误挡在消耗 macOS CI 额度之前。
//
// 约束：只允许 import Foundation。任何 Apple-only 框架都会让 Windows 编译失败。
import PackageDescription

let package = Package(
    name: "SHCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SHCore", targets: ["SHCore"]),
    ],
    targets: [
        .target(name: "SHCore"),
        .testTarget(name: "SHCoreTests", dependencies: ["SHCore"]),
    ]
)
