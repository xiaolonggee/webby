// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Webby", platforms: [.macOS(.v14)], products: [.executable(name: "Webby", targets: ["Webby"])], targets: [.target(name: "WebbyCore"), .executableTarget(name: "Webby", dependencies: ["WebbyCore"]), .testTarget(name: "WebbyCoreTests", dependencies: ["WebbyCore"]), .testTarget(name: "WebbyAppTests", dependencies: ["Webby"])])
