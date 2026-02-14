// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MirrorScreen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CGVirtualDisplayBridge",
            path: "Sources/CGVirtualDisplayBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "MirrorScreen",
            dependencies: ["CGVirtualDisplayBridge"],
            path: "Sources/MirrorScreen",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ],
            plugins: []
        ),
    ]
)
