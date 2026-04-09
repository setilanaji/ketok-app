// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ketok",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ketok",
            path: "Ketok"
        )
    ]
)
