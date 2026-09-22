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
