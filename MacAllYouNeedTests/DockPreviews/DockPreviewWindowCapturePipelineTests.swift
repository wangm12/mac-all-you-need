import AppKit
import XCTest
@testable import MacAllYouNeed

final class DockPreviewWindowCapturePipelineTests: XCTestCase {
    @MainActor func testShouldCaptureRespectsDisableImagePreview() {
        var hub = DockHubSettings.default
        hub.advanced.disableImagePreview = true
        XCTAssertFalse(DockPreviewPermissionGate.shouldCaptureWindowImages(hub: hub))
        hub.advanced.disableImagePreview = false
        XCTAssertEqual(
            DockPreviewPermissionGate.shouldCaptureWindowImages(hub: hub),
            DockPreviewPermissionGate.screenRecordingGranted()
        )
    }

    @MainActor func testPipelineReadsCacheLifespanFromHub() {
        let diskStore = DockPreviewThumbnailDiskStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("dock-pipeline-test-\(UUID().uuidString)", isDirectory: true)
        )
        let cache = DockPreviewWindowCache(diskStore: diskStore)
        var hub = DockHubSettings.default
        hub.advanced.screenCaptureCacheLifespan = 45
        let pipeline = DockPreviewWindowCapturePipeline(
            cache: cache,
            diskStore: diskStore,
            enumerator: SystemWindowEnumerator(),
            thumbnailService: DockPreviewThumbnailService(),
            hubSettings: hub
        )
        XCTAssertEqual(pipeline.cacheLifespan, 45)
    }

    @MainActor func testIsDisplayCacheFreshWhenAllThumbnailsFresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-pipeline-fresh-\(UUID().uuidString)", isDirectory: true)
        let diskStore = DockPreviewThumbnailDiskStore(rootURL: root)
        let cache = DockPreviewWindowCache(diskStore: diskStore)
        var hub = DockHubSettings.default
        hub.advanced.screenCaptureCacheLifespan = 300
        let pipeline = DockPreviewWindowCapturePipeline(
            cache: cache,
            diskStore: diskStore,
            enumerator: SystemWindowEnumerator(),
            thumbnailService: DockPreviewThumbnailService(),
            hubSettings: hub
        )
        let pid: pid_t = 42_001
        let windowID = CGWindowID(99_001)
        _ = cache.update(
            entries: [
                DockPreviewWindowEntry(
                    id: windowID,
                    pid: pid,
                    title: "Test",
                    frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                    thumbnail: nil,
                    isMinimized: false,
                    isOnScreen: true
                ),
            ],
            for: pid
        )
        let image = makeTestCGImage()
        await diskStore.write(pid: pid, windowID: windowID, cgImage: image, capturedAt: Date())
        XCTAssertTrue(pipeline.isDisplayCacheFresh(pid: pid))
    }

    @MainActor func testIsDisplayCacheFreshWhenOnlyMinimizedWindows() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-pipeline-min-\(UUID().uuidString)", isDirectory: true)
        let diskStore = DockPreviewThumbnailDiskStore(rootURL: root)
        let cache = DockPreviewWindowCache(diskStore: diskStore)
        let pipeline = DockPreviewWindowCapturePipeline(
            cache: cache,
            diskStore: diskStore,
            enumerator: SystemWindowEnumerator(),
            thumbnailService: DockPreviewThumbnailService(),
            hubSettings: DockHubSettings.default
        )
        let pid: pid_t = 42_003
        _ = cache.update(
            entries: [
                DockPreviewWindowEntry(
                    id: 1,
                    pid: pid,
                    title: "Minimized tab",
                    frame: .zero,
                    thumbnail: nil,
                    isMinimized: true,
                    isOnScreen: false
                ),
            ],
            for: pid
        )
        XCTAssertTrue(pipeline.isDisplayCacheFresh(pid: pid))
        XCTAssertFalse(DockPreviewCaptureEligibility.canCapture(cache.readCached(pid: pid)[0]))
    }

    @MainActor func testRefreshAppIfNeededSkipsWhenFresh() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-pipeline-skip-\(UUID().uuidString)", isDirectory: true)
        let diskStore = DockPreviewThumbnailDiskStore(rootURL: root)
        let cache = DockPreviewWindowCache(diskStore: diskStore)
        struct NoOpEnumerator: WindowEnumerating {
            func windows(
                for pid: pid_t,
                settings: DockPreviewSettings,
                bundleIdentifier: String?,
                disableMinWindowSizeFilter: Bool
            ) async -> [DockPreviewWindowEntry] {
                XCTFail("enumerator should not run when cache is fresh")
                return []
            }
        }
        var hub = DockHubSettings.default
        hub.advanced.screenCaptureCacheLifespan = 300
        let pipeline = DockPreviewWindowCapturePipeline(
            cache: cache,
            diskStore: diskStore,
            enumerator: NoOpEnumerator(),
            thumbnailService: DockPreviewThumbnailService(),
            hubSettings: hub
        )
        let pid: pid_t = 42_002
        let windowID = CGWindowID(99_002)
        _ = cache.update(
            entries: [
                DockPreviewWindowEntry(
                    id: windowID,
                    pid: pid,
                    title: "Fresh",
                    frame: .zero,
                    thumbnail: nil,
                    isMinimized: false,
                    isOnScreen: true
                ),
            ],
            for: pid
        )
        let image = makeTestCGImage()
        await diskStore.write(pid: pid, windowID: windowID, cgImage: image, capturedAt: Date())
        await pipeline.refreshAppIfNeeded(pid: pid, bundleIdentifier: "test.app")
    }

    private func makeTestCGImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
