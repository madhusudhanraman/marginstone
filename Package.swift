// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Nautilus", platforms: [.macOS(.v13)], products: [.executable(name: "Nautilus", targets: ["Nautilus"])], targets: [
    .target(name: "NautilusCore"),
    .executableTarget(name: "Nautilus", dependencies: ["NautilusCore"], resources: [.copy("Resources")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]),
    .testTarget(name: "NautilusCoreTests", dependencies: ["NautilusCore"])
], swiftLanguageVersions: [.v5])
