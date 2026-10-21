// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HermesMonitor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "HermesMonitor", targets: ["HermesMonitor"])],
    targets: [
        .executableTarget(name: "HermesMonitor"),
        .testTarget(name: "HermesMonitorTests", dependencies: ["HermesMonitor"])
    ]
)
