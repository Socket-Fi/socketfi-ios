// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SocketFiIOS",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SocketFiNativeKit", targets: ["SocketFiNativeKit"]),
    ],
    targets: [
        .target(name: "SocketFiNativeKit"),
        .testTarget(
            name: "SocketFiNativeKitTests",
            dependencies: ["SocketFiNativeKit"]
        ),
    ]
)
