// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/emqx/CocoaMQTT.git", from: "2.1.0")
    ],
    targets: [
        .executableTarget(
            name: "DesktopPet",
            dependencies: ["CocoaMQTT"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
