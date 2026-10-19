// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightCRMCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "LightCRMCore", targets: ["LightCRMCore"])],
    targets: [
        .target(name: "LightCRMCore", path: "Light CRM", exclude: ["ContentView.swift", "MyApp.swift", "Views", "Assets.xcassets", "Resources"], sources: ["Models", "Storage"]),
        .testTarget(name: "LightCRMCoreTests", dependencies: ["LightCRMCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
