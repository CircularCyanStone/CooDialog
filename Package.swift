// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CooDialog",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CooDialog",
            targets: ["CooDialog"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CooDialog"
        ),
        .testTarget(
            name: "CooDialogTests",
            dependencies: ["CooDialog"]
        ),
    ],
    // 显式声明 Swift 6 语言模式（严格并发检查），不依赖 tools-version 的默认值。
    // CooDialog 的公开 API 全部为 @MainActor 隔离，需在主线程调用。
    swiftLanguageModes: [.v6]
)
