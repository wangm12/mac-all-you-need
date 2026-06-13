import Core
import os

extension DockPreviewCoordinator {
    func beginHoverShowMeasurement(pid: pid_t) {
        endHoverShowMeasurementIfNeeded()
        hoverShowSignpost = PerformanceSignpost.DockCapture.beginHoverShow(pid: pid)
    }

    func endHoverShowMeasurementIfNeeded() {
        if let firstThumbnailSignpost {
            PerformanceSignpost.DockCapture.endFirstThumbnailRender(firstThumbnailSignpost)
            self.firstThumbnailSignpost = nil
        }
        if let hoverShowSignpost {
            PerformanceSignpost.DockCapture.endHoverShow(hoverShowSignpost)
            self.hoverShowSignpost = nil
        }
    }

    func beginFirstThumbnailMeasurement(count: Int) {
        if firstThumbnailSignpost == nil {
            firstThumbnailSignpost = PerformanceSignpost.DockCapture.beginFirstThumbnailRender(count: count)
        }
    }
}
