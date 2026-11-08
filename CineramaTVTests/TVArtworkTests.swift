import Testing
import UIKit
@testable import CineramaTV

@Suite("TV artwork memory bounds")
struct TVArtworkTests {
    @Test func oversizedArtworkIsDecodedAtDisplaySize() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format)
            .pngData { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
            }
        let image = try #require(TVArtworkDecoder.thumbnail(source, maxPixelSize: 340)?.cgImage)
        #expect(image.width == 340)
        #expect(image.height == 170)
        #expect(image.bytesPerRow * image.height < 340 * 170 * 8)
    }

    @Test func invalidArtworkAndInvalidSizeFailSafely() {
        #expect(TVArtworkDecoder.thumbnail(Data([0, 1, 2]), maxPixelSize: 220) == nil)
        #expect(TVArtworkDecoder.thumbnail(Data(), maxPixelSize: 0) == nil)
    }
}
