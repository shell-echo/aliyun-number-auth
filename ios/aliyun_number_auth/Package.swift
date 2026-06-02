// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "aliyun_number_auth",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "aliyun-number-auth", targets: ["aliyun_number_auth"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "aliyun_number_auth",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "ATAuthSDK",
                "YTXMonitor",
                "YTXOperators",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            // ATAuthSDK uses Objective-C categories on UIViewController to present the
            // login page. ObjC categories in static xcframeworks are not automatically
            // linked by the linker — -ObjC forces them in. Without this flag,
            // getLoginToken crashes with "unrecognized selector" at runtime.
            linkerSettings: [
                .unsafeFlags(["-ObjC"], .when(platforms: [.iOS]))
            ]
        ),
        .binaryTarget(name: "ATAuthSDK",    path: "Frameworks/ATAuthSDK.xcframework"),
        .binaryTarget(name: "YTXMonitor",   path: "Frameworks/YTXMonitor.xcframework"),
        .binaryTarget(name: "YTXOperators", path: "Frameworks/YTXOperators.xcframework"),
    ]
)
