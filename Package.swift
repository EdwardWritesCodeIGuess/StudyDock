// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudyDock",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.executable(name: "StudyDock", targets: ["StudyDockApp"])],
    targets: [
        .target(name: "StudyDockCore"),
        .executableTarget(name: "StudyDockApp", dependencies: ["StudyDockCore"]),
        .testTarget(name: "StudyDockCoreTests", dependencies: ["StudyDockCore"])
    ]
)
