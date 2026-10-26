// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetalMPEG2Prototype",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "mpeg2-metal-benchmark", targets: ["MPEG2Benchmark"])],
    targets: [
        .target(name: "MPEG2Reconstruction", resources: [.copy("Reconstruct.metal")]),
        .executableTarget(name: "MPEG2Benchmark", dependencies: ["MPEG2Reconstruction"]),
        .testTarget(name: "MPEG2ReconstructionTests", dependencies: ["MPEG2Reconstruction"])
    ]
)
