// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloseNLid",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CloseNLid",
            path: "Sources/CloseNLid"
        )
    ]
)
