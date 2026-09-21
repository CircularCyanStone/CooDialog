// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CooDialog",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "CooDialog",
            targets: ["CooDialog"]
        ),
    ],
    targets: [
        .target(
            name: "CooDialog",
            // 如果你的代码里用到了 UIKit，部分 Xcode 版本或 Swift 版本下
            // 明确加上 linkerSettings 或确保 iOS 平台生效会有所帮助。
            // 通常只需确保 platforms 先生效，若依然报错，可尝试通过以下方式清理缓存。
            dependencies: []
        ),
        .testTarget(
            name: "CooDialogTests",
            dependencies: ["CooDialog"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
