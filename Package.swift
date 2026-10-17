// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Marginstone", platforms: [.macOS(.v13)], products: [.executable(name: "Marginstone", targets: ["Marginstone"])], targets: [
    .target(name: "MarginstoneCore"),
    .executableTarget(name: "Marginstone", dependencies: ["MarginstoneCore"], resources: [.copy("Resources")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("PDFKit"), .linkedFramework("Vision")]),
    .testTarget(name: "MarginstoneCoreTests", dependencies: ["MarginstoneCore"])
], swiftLanguageVersions: [.v5])
