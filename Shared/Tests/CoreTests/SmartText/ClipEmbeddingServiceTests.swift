@testable import Core
import XCTest

final class ClipEmbeddingServiceTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let v: [Float] = [1.5, -2.25, 0, 3.14159, 100]
        let data = ClipEmbeddingService.encode(v)
        let back = ClipEmbeddingService.decode(data)
        XCTAssertEqual(back, v)
    }

    func testDecodeRejectsMisalignedData() {
        XCTAssertNil(ClipEmbeddingService.decode(Data([1, 2, 3])))
    }

    func testCosineIdentical() {
        let v: [Float] = [1, 2, 3]
        XCTAssertEqual(ClipEmbeddingService.cosine(v, v), 1.0, accuracy: 1e-6)
    }

    func testCosineOrthogonal() {
        XCTAssertEqual(ClipEmbeddingService.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }

    func testCosineMismatchedLengthsIsZero() {
        XCTAssertEqual(ClipEmbeddingService.cosine([1, 2], [1, 2, 3]), 0.0)
    }

    func testCosineEmptyIsZero() {
        XCTAssertEqual(ClipEmbeddingService.cosine([], []), 0.0)
    }
}
