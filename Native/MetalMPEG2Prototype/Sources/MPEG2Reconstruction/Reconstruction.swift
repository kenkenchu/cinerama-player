import Foundation
import Metal

public enum PrototypeError: Error {
    case invalidInput(String)
    case metalUnavailable
    case metalFailure(String)
}

/// Progressive frame prediction only; vectors are in half-pixels of THIS plane.
/// Callers must derive chroma vectors separately. Field/dual-prime modes cannot
/// be represented and must be rejected by a future bitstream adapter.
public struct BlockPrediction: Sendable {
    public enum Mode: Int32, Sendable { case intra, forward, backward, bidirectional }
    var mode: Int32
    var forwardX: Int32
    var forwardY: Int32
    var backwardX: Int32
    var backwardY: Int32
    public init(_ mode: Mode, forwardX: Int32 = 0, forwardY: Int32 = 0,
                backwardX: Int32 = 0, backwardY: Int32 = 0) {
        self.mode = mode.rawValue
        self.forwardX = forwardX; self.forwardY = forwardY
        self.backwardX = backwardX; self.backwardY = backwardY
    }
}

/// One tightly packed 8-bit plane with row-major 8x8 blocks. Does not parse MPEG
/// bytes. Coefficients must already be inverse-quantized, natural-order, clamped
/// to [-2048,2047], with intra DC scaling and MPEG-2 mismatch control applied.
public struct ReconstructionInput: Sendable {
    public let width: Int
    public let height: Int
    public let coefficients: [Int16]
    public let predictions: [BlockPrediction]
    public let forward: [UInt8]
    public let backward: [UInt8]

    public init(width: Int, height: Int, coefficients: [Int16],
                predictions: [BlockPrediction], forward: [UInt8] = [], backward: [UInt8] = []) throws {
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              width.isMultiple(of: 8), height.isMultiple(of: 8) else {
            throw PrototypeError.invalidInput("Plane dimensions must be multiples of 8 in 8...2048")
        }
        let pixels = width * height
        guard coefficients.count == pixels, predictions.count == pixels / 64,
              coefficients.allSatisfy({ (-2048...2047).contains(Int($0)) }) else {
            throw PrototypeError.invalidInput("Invalid coefficient/block count or coefficient range")
        }
        let needsForward = predictions.contains { $0.mode == 1 || $0.mode == 3 }
        let needsBackward = predictions.contains { $0.mode == 2 || $0.mode == 3 }
        guard (!needsForward || forward.count == pixels), (!needsBackward || backward.count == pixels),
              forward.isEmpty || forward.count == pixels, backward.isEmpty || backward.count == pixels,
              predictions.allSatisfy({ p in
                  [p.forwardX, p.forwardY, p.backwardX, p.backwardY].allSatisfy { (-4096...4096).contains($0) }
              }) else {
            throw PrototypeError.invalidInput("Missing/invalid reference plane or out-of-range motion vector")
        }
        self.width = width; self.height = height
        self.coefficients = coefficients; self.predictions = predictions
        self.forward = forward; self.backward = backward
    }
}

// C(x,u) = (u == 0 ? 1/sqrt(2) : 1) * cos((2x+1)u*pi/16) / 2
private let basis: [Double] = (0..<64).map { i in
    let x = i / 8, u = i % 8
    return (u == 0 ? 1 / sqrt(2.0) : 1) * cos(Double((2*x+1)*u) * .pi / 16) / 2
}

/// Scalar Double-precision oracle, not an optimized production CPU decoder.
public func reconstructCPU(_ input: ReconstructionInput) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: input.width * input.height)
    func predict(_ plane: [UInt8], _ x: Int, _ y: Int, _ dx: Int32, _ dy: Int32) -> Int {
        let ix = Int(floor(Double(dx)/2)), iy = Int(floor(Double(dy)/2))
        let hx = Int(dx) - 2*ix, hy = Int(dy) - 2*iy
        func pixel(_ a: Int, _ b: Int) -> Int {
            Int(plane[min(input.height-1,max(0,b))*input.width + min(input.width-1,max(0,a))])
        }
        let a = pixel(x+ix,y+iy)
        if hx == 0 && hy == 0 { return a }
        if hy == 0 { return (a + pixel(x+ix+1,y+iy) + 1)/2 }
        if hx == 0 { return (a + pixel(x+ix,y+iy+1) + 1)/2 }
        return (a + pixel(x+ix+1,y+iy) + pixel(x+ix,y+iy+1) + pixel(x+ix+1,y+iy+1) + 2)/4
    }
    for (block,p) in input.predictions.enumerated() {
        var rows = [Double](repeating: 0, count: 64)
        for v in 0..<8 { for x in 0..<8 {
            for u in 0..<8 { rows[v*8+x] += Double(input.coefficients[block*64+v*8+u]) * basis[x*8+u] }
        } }
        for y in 0..<8 { for x in 0..<8 {
            var value = 0.0
            for v in 0..<8 { value += rows[v*8+x] * basis[y*8+v] }
            let px = block % (input.width/8)*8+x, py = block / (input.width/8)*8+y
            var prediction = 0
            if p.mode == 1 || p.mode == 3 { prediction = predict(input.forward,px,py,p.forwardX,p.forwardY) }
            if p.mode == 2 { prediction = predict(input.backward,px,py,p.backwardX,p.backwardY) }
            if p.mode == 3 { prediction = (prediction + predict(input.backward,px,py,p.backwardX,p.backwardY) + 1)/2 }
            output[py*input.width+px] = UInt8(clamping: Int(floor(value+0.5)) + prediction)
        } }
    }
    return output
}

/// Synchronous harness. A prepared job owns reusable shared buffers; steady-state
/// timings exclude preparation/upload, but include command submission and wait.
/// Jobs and this class are intentionally not Sendable.
public final class MetalReconstructor {
    public let deviceName: String
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let basisBuffer: MTLBuffer

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw PrototypeError.metalUnavailable
        }
        self.device = device; self.queue = queue; deviceName = device.name
        let url = Bundle.module.url(forResource: "Reconstruct", withExtension: "metal")!
        let options = MTLCompileOptions()
        options.mathMode = .safe
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
        guard let function = library.makeFunction(name: "reconstruct") else {
            throw PrototypeError.metalFailure("Missing reconstruction kernel")
        }
        pipeline = try device.makeComputePipelineState(function: function)
        guard pipeline.maxTotalThreadsPerThreadgroup >= 64,
              MemoryLayout<BlockPrediction>.stride == 20 else {
            throw PrototypeError.metalFailure("Unsupported threadgroup limit or prediction ABI")
        }
        basisBuffer = try Self.buffer(device, basis.map(Float.init))
    }

    private static func buffer<T>(_ device: MTLDevice, _ data: [T]) throws -> MTLBuffer {
        let result = data.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        guard let result else { throw PrototypeError.metalFailure("Buffer allocation failed") }
        return result
    }

    public final class Job {
        fileprivate let buffers: [MTLBuffer]
        fileprivate let width: Int
        fileprivate let height: Int
        fileprivate let owner: MetalReconstructor
        fileprivate init(buffers: [MTLBuffer], input: ReconstructionInput, owner: MetalReconstructor) {
            self.buffers = buffers; width = input.width; height = input.height; self.owner = owner
        }
        public func pixels() -> [UInt8] {
            Array(UnsafeBufferPointer(start: buffers[4].contents().assumingMemoryBound(to: UInt8.self), count: width*height))
        }
    }
    public func prepare(_ input: ReconstructionInput) throws -> Job {
        let pixels = input.width * input.height
        guard let output = device.makeBuffer(length: pixels, options: .storageModeShared) else {
            throw PrototypeError.metalFailure("Output allocation failed")
        }
        let buffers = try [Self.buffer(device,input.coefficients), Self.buffer(device,input.predictions),
                           Self.buffer(device,input.forward.isEmpty ? [0] : input.forward),
                           Self.buffer(device,input.backward.isEmpty ? [0] : input.backward), output, basisBuffer]
        return Job(buffers: buffers, input: input, owner: self)
    }
    /// GPU execution seconds (excludes CPU submission/wait); zero if unavailable.
    @discardableResult public func run(_ job: Job) throws -> Double {
        guard job.owner === self else { throw PrototypeError.invalidInput("Job belongs to another reconstructor") }
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw PrototypeError.metalFailure("Command allocation failed")
        }
        encoder.setComputePipelineState(pipeline)
        for (i,buffer) in job.buffers.enumerated() { encoder.setBuffer(buffer,offset: 0,index: i) }
        var dimensions = SIMD2<UInt32>(UInt32(job.width),UInt32(job.height))
        encoder.setBytes(&dimensions,length: MemoryLayout.size(ofValue: dimensions),index: 6)
        encoder.dispatchThreadgroups(MTLSize(width: job.width*job.height/64,height: 1,depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: 64,height: 1,depth: 1))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else {
            throw PrototypeError.metalFailure(command.error?.localizedDescription ?? "GPU command failed")
        }
        return max(0,command.gpuEndTime-command.gpuStartTime)
    }
}
