// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacPulse", targets: ["MacPulse"])
    ],
    targets: [
        .executableTarget(
            name: "MacPulse",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags([
                    "-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
                ])
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreWLAN"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MacPulseTests",
            dependencies: ["MacPulse"],
            swiftSettings: [
                .unsafeFlags([
                    "-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
                ])
            ]
        ),
    ]
)
