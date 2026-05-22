import Core
import SwiftUI

// MARK: - Drop resolver (hit-testing + accept/reject)

enum DockListTabDropResolver {
    private static let verticalTolerance: CGFloat = 12
    private static let nearestHorizontalTolerance: CGFloat = 24
    private static let appendAfterLastHorizontalTolerance: CGFloat = 80

    static func targetSelector(
        at location: CGPoint,
        in frames: [DockListTabDropFrame],
        requiresItemDropTarget: Bool
    ) -> DockListSelector? {
        guard !frames.isEmpty else { return nil }
        let candidates = requiresItemDropTarget ? frames.filter(\.acceptsItemDrop) : frames

        if let direct = candidates.first(where: { $0.hitRect.contains(location) }) {
            return direct.selector
        }

        if requiresItemDropTarget,
           frames.contains(where: { !$0.acceptsItemDrop && $0.hitRect.contains(location) })
        {
            return nil
        }

        guard let verticalRange = frames.verticalRange,
              location.y >= verticalRange.lowerBound - verticalTolerance,
              location.y <= verticalRange.upperBound + verticalTolerance
        else { return nil }

        let nearest = candidates.min { lhs, rhs in
            lhs.horizontalDistance(to: location.x) < rhs.horizontalDistance(to: location.x)
        }
        guard let nearest,
              nearest.horizontalDistance(to: location.x) <= nearestHorizontalTolerance
        else { return nil }
        return nearest.selector
    }

    static func reorderTarget(
        at location: CGPoint,
        in frames: [DockListTabDropFrame]
    ) -> DockListTabReorderTarget? {
        let pinboardFrames = frames.filter(\.isPinboard).sorted { $0.rect.minX < $1.rect.minX }
        guard !pinboardFrames.isEmpty else { return nil }

        if frames.contains(where: { !$0.isPinboard && $0.hitRect.contains(location) }) {
            return nil
        }

        guard let verticalRange = frames.verticalRange,
              location.y >= verticalRange.lowerBound - verticalTolerance,
              location.y <= verticalRange.upperBound + verticalTolerance
        else { return nil }

        if let direct = pinboardFrames.first(where: { $0.hitRect.contains(location) }),
           case let .pinboard(id) = direct.selector
        {
            return DockListTabReorderTarget(
                targetID: id,
                placement: location.x < direct.rect.midX ? .before : .after
            )
        }

        if let last = pinboardFrames.last,
           location.x > last.rect.maxX,
           location.x <= last.rect.maxX + appendAfterLastHorizontalTolerance,
           case let .pinboard(id) = last.selector
        {
            return DockListTabReorderTarget(targetID: id, placement: .after)
        }

        if let first = pinboardFrames.first,
           location.x < first.rect.minX,
           first.rect.minX - location.x <= nearestHorizontalTolerance,
           case let .pinboard(id) = first.selector
        {
            return DockListTabReorderTarget(targetID: id, placement: .before)
        }

        return nil
    }
}

// MARK: - Preference key + frame reporter

struct DockListTabDropFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DockListTabDropFrame] = []

    static func reduce(value: inout [DockListTabDropFrame], nextValue: () -> [DockListTabDropFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct DockListTabFrameReporter: View {
    let selector: DockListSelector

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DockListTabDropFramePreferenceKey.self,
                value: [
                    DockListTabDropFrame(
                        selector: selector,
                        rect: proxy.frame(in: .named(DockListTabsPresentation.dropCoordinateSpace))
                    )
                ]
            )
        }
    }
}
