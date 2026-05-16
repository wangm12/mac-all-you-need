import XCTest
import SwiftUI
@testable import FeatureCore

private func makeDescriptor(_ id: FeatureID) -> FeatureDescriptor {
    FeatureDescriptor(
        id: id, displayName: id.rawValue, icon: "circle",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
}

final class FeatureRegistryTests: XCTestCase {
    func testIterationOrder() {
        let registry = FeatureRegistry(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.folderPreview),
            makeDescriptor(.downloader),
            makeDescriptor(.voice),
        ])
        XCTAssertEqual(registry.descriptors.map(\.id), [.clipboard, .folderPreview, .downloader, .voice])
    }

    func testLookupById() {
        let registry = FeatureRegistry(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.voice),
        ])
        XCTAssertNotNil(registry.descriptor(for: .clipboard))
        XCTAssertNotNil(registry.descriptor(for: .voice))
        XCTAssertNil(registry.descriptor(for: .downloader))
    }

    func testRejectsDuplicateIDs() {
        XCTAssertThrowsError(try FeatureRegistry.validated(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.clipboard),
        ])) { error in
            XCTAssertEqual(error as? FeatureRegistry.ValidationError, .duplicateID(.clipboard))
        }
    }
}
