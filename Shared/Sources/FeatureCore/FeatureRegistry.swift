import Foundation

public struct FeatureRegistry: Sendable {
    public let descriptors: [FeatureDescriptor]

    public init(descriptors: [FeatureDescriptor]) {
        self.descriptors = descriptors
    }

    public func descriptor(for id: FeatureID) -> FeatureDescriptor? {
        descriptors.first(where: { $0.id == id })
    }

    public enum ValidationError: Error, Equatable {
        case duplicateID(FeatureID)
    }

    public static func validated(descriptors: [FeatureDescriptor]) throws -> FeatureRegistry {
        var seen = Set<FeatureID>()
        for d in descriptors {
            if !seen.insert(d.id).inserted {
                throw ValidationError.duplicateID(d.id)
            }
        }
        return FeatureRegistry(descriptors: descriptors)
    }
}
