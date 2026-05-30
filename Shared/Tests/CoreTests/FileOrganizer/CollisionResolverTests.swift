import XCTest
@testable import Core

final class CollisionResolverTests: XCTestCase {
    func testNoCollisionReturnsDesired() { XCTAssertEqual(CollisionResolver.resolve(desired: "a.txt", existing: []), "a.txt") }
    func testFirstCollisionAdds2() { XCTAssertEqual(CollisionResolver.resolve(desired: "a.txt", existing: ["a.txt"]), "a (2).txt") }
    func testChainedCollisions() { XCTAssertEqual(CollisionResolver.resolve(desired: "a.txt", existing: ["a.txt", "a (2).txt"]), "a (3).txt") }
    func testNoExtension() { XCTAssertEqual(CollisionResolver.resolve(desired: "README", existing: ["README"]), "README (2)") }
}
