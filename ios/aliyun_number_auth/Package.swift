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
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        ),
        .binaryTarget(name: "ATAuthSDK",    path: "Frameworks/ATAuthSDK.xcframework"),
        .binaryTarget(name: "YTXMonitor",   path: "Frameworks/YTXMonitor.xcframework"),
        .binaryTarget(name: "YTXOperators", path: "Frameworks/YTXOperators.xcframework"),
    ]
)
