// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Jarvis", targets: ["JarvisApp"]),
        .library(name: "JarvisKit", targets: ["JarvisKit"]),
    ],
    targets: [
        // Prebuilt llama.cpp (Metal), so Jarvis can run a local model with no Ollama.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11588/llama-b11588-xcframework.zip",
            checksum: "4efb28d65a9e4bade3e1d0aeeaf6094206de85b7ad77da2cb585a938bfb1f052"),
        .target(name: "JarvisKit", dependencies: ["llama"]),
        .executableTarget(name: "JarvisApp", dependencies: ["JarvisKit"]),
        .testTarget(name: "JarvisKitTests", dependencies: ["JarvisKit"]),
    ]
)
