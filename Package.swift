// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// 取 6.0 而非更高：源码没有使用 6.1 / 6.2 的特性（`swiftLanguageModes` 本身也是 6.0 引入的 API），
// 门槛定在 6.0 可以让 Xcode 16 及以上的工具链都能解析这个包。

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
            // 纯 UIKit 实现，无第三方依赖；平台与最低版本由上面的 platforms 声明
            dependencies: []
        ),
        .testTarget(
            name: "CooDialogTests",
            dependencies: ["CooDialog"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
