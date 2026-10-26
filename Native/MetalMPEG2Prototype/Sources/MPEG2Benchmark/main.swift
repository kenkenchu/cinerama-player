import Foundation
import MPEG2Reconstruction

// Deterministic padded HD luma workload; no media, credentials or networking.
// All stages before inverse DCT are deliberately outside this experiment.
let width = 1920, height = 1088, iterations = 60
let pixels = width * height
var coefficients = [Int16](repeating: 0,count: pixels)
var predictions: [BlockPrediction] = []
for block in 0..<pixels/64 {
    let mode = BlockPrediction.Mode(rawValue: Int32(block % 4))!
    coefficients[block*64] = mode == .intra ? 1024 : 48
    coefficients[block*64+1] = 32
    coefficients[block*64+8] = -24
    predictions.append(.init(mode,forwardX: -1,forwardY: 1,backwardX: 3,backwardY: -1))
}
let input = try ReconstructionInput(width: width,height: height,coefficients: coefficients,predictions: predictions,
    forward: (0..<pixels).map { UInt8(($0 % width)/8 % 256) },
    backward: (0..<pixels).map { UInt8(($0 / width)/4 % 256) })
let metal = try MetalReconstructor()
let preparationStart = ProcessInfo.processInfo.systemUptime
let job = try metal.prepare(input)
let preparation = ProcessInfo.processInfo.systemUptime-preparationStart
for _ in 0..<5 { try metal.run(job) }
var gpuSeconds = 0.0
let start = ProcessInfo.processInfo.systemUptime
for _ in 0..<iterations { gpuSeconds += try metal.run(job) }
let wall = ProcessInfo.processInfo.systemUptime-start
let cpuStart = ProcessInfo.processInfo.systemUptime
let expected = reconstructCPU(input)
let cpuWall = ProcessInfo.processInfo.systemUptime-cpuStart
let actual = job.pixels()
var maxError = 0, changed = 0
for (a,b) in zip(actual,expected) {
    let error = abs(Int(a)-Int(b)); maxError = max(maxError,error)
    if error > 0 { changed += 1 }
}
guard maxError <= 1 else { fatalError("CPU/GPU validation failed: maximum pixel error \(maxError)") }
print("GPU: \(metal.deviceName)")
print("Synthetic reconstruction only: \(width)x\(height) luma; \(iterations) iterations; mixed intra/forward/backward/bidirectional")
print(String(format: "Prepare buffers: %.3f ms",preparation*1000))
print(String(format: "Mean GPU execution: %.3f ms/plane",gpuSeconds*1000/Double(iterations)))
print(String(format: "Mean submission + GPU + synchronous wait: %.3f ms/plane",wall*1000/Double(iterations)))
print(String(format: "Scalar Double CPU oracle (one plane, NOT VLC/FFmpeg): %.3f ms",cpuWall*1000))
print("CPU/GPU maximum pixel difference: \(maxError); differing pixels: \(changed)/\(pixels)")
print("Excludes entropy decoding, inverse quantization, chroma, field prediction, deinterlacing, audio, rendering and per-frame uploads.")
print("Does not measure Live TV CPU savings, energy, MPEG-2 conformance or end-to-end decoder throughput.")
