// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassLink",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "GlassLink", targets: ["GlassLink"]),
        .library(name: "KDEConnectKit", targets: ["KDEConnectKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.30.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.10.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.10.0"..<"5.0.0"),
    ],
    targets: [
        // KDE Connect protocol: discovery, TLS links, pairing, packets, payload transfers. No UI.
        .target(
            name: "KDEConnectKit",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The macOS app: SwiftUI, Liquid Glass, menu bar extra, notifications.
        .executableTarget(
            name: "GlassLink",
            dependencies: ["KDEConnectKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "KDEConnectKitTests",
            dependencies: [
                "KDEConnectKit",
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
