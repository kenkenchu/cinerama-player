import XCTest
@testable import MPEG2Reconstruction

final class ReconstructionTests: XCTestCase {
    func gpu(_ input: ReconstructionInput) throws -> [UInt8] {
        let metal = try MetalReconstructor()
        let job = try metal.prepare(input)
        try metal.run(job)
        return job.pixels()
    }
    func testIntraDCScalingAndClipping() throws {
        // MPEG intra DC is already scaled at this boundary: DC/8 = pixel.
        for (dc, expected) in [(0,0),(800,100),(2040,255),(-2048,0)] {
            var c = [Int16](repeating: 0,count: 64); c[0] = Int16(dc)
            let input = try ReconstructionInput(width: 8,height: 8,coefficients: c,predictions: [.init(.intra)])
            XCTAssertEqual(try gpu(input),[UInt8](repeating: UInt8(expected),count: 64))
            XCTAssertEqual(reconstructCPU(input),[UInt8](repeating: UInt8(expected),count: 64))
        }
    }
    func testHalfPixelPredictionAllDirectionsAndBorders() throws {
        let reference: [UInt8] = (0..<256).map { (i: Int) -> UInt8 in
            let x = (i % 16) * 7
            let y = (i / 16) * 3
            return UInt8(x + y)
        }
        for dy in -3...3 { for dx in -3...3 {
            let input = try ReconstructionInput(width: 16,height: 16,
                coefficients: .init(repeating: 0,count: 256),
                predictions: .init(repeating: .init(.forward,forwardX: Int32(dx),forwardY: Int32(dy)),count: 4),
                forward: reference)
            XCTAssertEqual(try gpu(input),reconstructCPU(input),"Motion \(dx),\(dy)")
        } }
    }
    func testKnownPredictionRounding() throws {
        // At (0,0), diagonal prediction = (0+1+8+9+2)/4 = 5.
        let plane = (0..<64).map(UInt8.init)
        let input = try ReconstructionInput(width: 8,height: 8,coefficients: .init(repeating: 0,count: 64),
            predictions: [.init(.forward,forwardX: 1,forwardY: 1)],forward: plane)
        XCTAssertEqual(try gpu(input)[0],5)
        let negative = try ReconstructionInput(width: 8,height: 8,coefficients: .init(repeating: 0,count: 64),
            predictions: [.init(.forward,forwardX: -1,forwardY: -1)],forward: plane)
        let pixels = try gpu(negative)
        XCTAssertEqual(pixels[0],0)
        XCTAssertEqual(pixels[9],5) // (0+1+8+9+2)/4, not truncation toward zero.
    }
    func testBackwardAndBidirectionalWithResidual() throws {
        var c = [Int16](repeating: 0,count: 64); c[0] = 80 // residual +10
        for (mode,expected) in [(BlockPrediction.Mode.backward,211),(.bidirectional,161)] {
            let input = try ReconstructionInput(width: 8,height: 8,coefficients: c,predictions: [.init(mode)],
                forward: .init(repeating: 100,count: 64),backward: .init(repeating: 201,count: 64))
            XCTAssertEqual(try gpu(input),.init(repeating: UInt8(expected),count: 64))
        }
    }
    func testACImpulseAgainstAnalyticIDCT() throws {
        var c = [Int16](repeating: 0,count: 64); c[0] = 1024; c[1] = 128
        let input = try ReconstructionInput(width: 8,height: 8,coefficients: c,predictions: [.init(.intra)])
        let output = try gpu(input)
        for y in 0..<8 { for x in 0..<8 {
            let value = 128 + 128/(4*sqrt(2.0))*cos(Double(2*x+1)*Double.pi/16)
            XCTAssertEqual(Int(output[y*8+x]),Int(floor(value+0.5)))
        } }
    }
    func testDeterministicMixedBlocksAgainstDoubleOracle() throws {
        var state: UInt64 = 42
        func random(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1
            return Int((state >> 32) % UInt64(bound))
        }
        let n = 64*64
        let coeffs = (0..<n).map { _ in Int16(random(513)-256) }
        let forward = (0..<n).map { _ in UInt8(random(256)) }
        let backward = (0..<n).map { _ in UInt8(random(256)) }
        let predictions = (0..<n/64).map { b in
            BlockPrediction(BlockPrediction.Mode(rawValue: Int32(b % 4))!,
                forwardX: Int32(random(33)-16),forwardY: Int32(random(33)-16),
                backwardX: Int32(random(33)-16),backwardY: Int32(random(33)-16))
        }
        let input = try ReconstructionInput(width: 64,height: 64,coefficients: coeffs,
            predictions: predictions,forward: forward,backward: backward)
        let actual = try gpu(input), expected = reconstructCPU(input)
        XCTAssertLessThanOrEqual(zip(actual,expected).map { abs(Int($0)-Int($1)) }.max()!,1)
    }
    func testRejectsInvalidInputs() throws {
        for (w,h) in [(0,8),(-8,8),(9,8),(Int.max,8),(8,2056)] {
            XCTAssertThrowsError(try ReconstructionInput(width: w,height: h,coefficients: [],predictions: []))
        }
        XCTAssertThrowsError(try ReconstructionInput(width: 8,height: 8,coefficients: [],predictions: []))
        XCTAssertThrowsError(try ReconstructionInput(width: 8,height: 8,
            coefficients: .init(repeating: 2048,count: 64),predictions: [.init(.intra)]))
        XCTAssertThrowsError(try ReconstructionInput(width: 8,height: 8,
            coefficients: .init(repeating: 0,count: 64),predictions: [.init(.forward)]))
        XCTAssertThrowsError(try ReconstructionInput(width: 8,height: 8,
            coefficients: .init(repeating: 0,count: 64),predictions: [.init(.backward)],backward: [1]))
        XCTAssertThrowsError(try ReconstructionInput(width: 8,height: 8,
            coefficients: .init(repeating: 0,count: 64),predictions: [.init(.intra,forwardX: Int32.max)]))
    }
    func testJobOwnershipAndRepeatDispatch() throws {
        let a = try MetalReconstructor(), b = try MetalReconstructor()
        let input = try ReconstructionInput(width: 8,height: 8,
            coefficients: .init(repeating: 0,count: 64),predictions: [.init(.intra)])
        let job = try a.prepare(input)
        XCTAssertThrowsError(try b.run(job))
        for _ in 0..<3 { try a.run(job); XCTAssertEqual(job.pixels(),.init(repeating: 0,count: 64)) }
    }
}
