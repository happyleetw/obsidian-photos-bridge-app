// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ObsidianPhotosBridge",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ObsidianPhotosBridge", targets: ["ObsidianPhotosBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/yene/GCDWebServer.git", from: "3.5.7")
    ],
    targets: [
        .executableTarget(
            name: "ObsidianPhotosBridge",
            dependencies: ["GCDWebServer"],
            path: "Sources"
        )
    ]
) 