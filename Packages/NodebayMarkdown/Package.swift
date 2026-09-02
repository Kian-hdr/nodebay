// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NodebayMarkdown",
    platforms: [.macOS("15.0")],
    products: [.library(name: "NodebayMarkdown", targets: ["NodebayMarkdown"])],
    targets: [
        .target(name: "NodebayMarkdown"),
        .testTarget(name: "NodebayMarkdownTests", dependencies: ["NodebayMarkdown"])
    ]
)
