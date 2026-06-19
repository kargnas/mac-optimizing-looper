// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "MacLoadAdvisor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacLoadAdvisorCore", targets: ["MacLoadAdvisorCore"]),
        .executable(name: "MacLoadAdvisor", targets: ["MacLoadAdvisor"])
    ],
    targets: [
        .target(name: "MacLoadAdvisorCore"),
        .executableTarget(name: "MacLoadAdvisor", dependencies: ["MacLoadAdvisorCore"]),
        .testTarget(name: "MacLoadAdvisorCoreTests", dependencies: ["MacLoadAdvisorCore"])
    ]
)
