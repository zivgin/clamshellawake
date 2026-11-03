// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClamshellAwake",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClamshellAwake",
            path: "Sources/ClamshellAwake",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
