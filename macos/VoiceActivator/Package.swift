// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceActivator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoiceActivator", targets: ["VoiceActivator"]),
    ],
    targets: [
        .executableTarget(
            name: "VoiceActivator",
            path: "Sources/VoiceActivator"
        ),
    ]
)
