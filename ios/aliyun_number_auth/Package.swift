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
                "ATAuthSDK_D",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .binaryTarget(name: "ATAuthSDK_D", path: "Frameworks/ATAuthSDK_D.xcframework"),
    ]
)
