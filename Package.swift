// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WindowLayoutMemory", platforms: [.macOS(.v13)],
    products: [.executable(name: "WindowLayoutMemory", targets: ["WindowLayoutMemory"]),
               .executable(name: "CoreTests", targets: ["CoreTests"])],
    targets: [.target(name: "LayoutCore"),
              .executableTarget(name: "WindowLayoutMemory", dependencies: ["LayoutCore"]),
              .executableTarget(name: "CoreTests", dependencies: ["LayoutCore"], path: "Tests/CoreTests")]
)
