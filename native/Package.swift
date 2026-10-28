// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KMSA",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "KMSA", targets: ["KMSA"]),
               .executable(name: "KMSAUpdateInstaller", targets: ["KMSAUpdateInstaller"])],
    targets: [
        .target(name: "KMSACore"),
        .executableTarget(name: "KMSA", dependencies: ["KMSACore"], resources: [.copy("Resources")]),
        .executableTarget(name: "KMSAUpdateInstaller", dependencies: ["KMSACore"]),
        .executableTarget(name: "KMSAChecks", dependencies: ["KMSACore"], path: "Tests/KMSACoreTests"),
    ]
)
