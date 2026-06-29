@testable import MacAllYouNeed
import AppKit
import Core
import XCTest

final class DockItemTests: XCTestCase {
    func testDeriveKindFromImageMeta() {
        let meta = ClipboardXPCMeta(
            id: "1",
            modified: Date(),
            kind: "clipboardItem",
            preview: "(image 32x32)",
            imageWidth: 32,
            imageHeight: 32,
            imageBlobID: "blob1"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .image(w, h, blobID) = item.kind else {
            XCTFail("expected image kind")
            return
        }
        XCTAssertEqual(w, 32)
        XCTAssertEqual(h, 32)
        XCTAssertEqual(blobID, "blob1")
    }

    func testDeriveKindFromTextWithURLPreview() {
        let meta = ClipboardXPCMeta(
            id: "2",
            modified: Date(),
            kind: "clipboardItem",
            preview: "https://example.com"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .link(url) = item.kind else {
            XCTFail("expected link")
            return
        }
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testDeriveKindFromTextWithColorPreview() {
        let meta = ClipboardXPCMeta(
            id: "3",
            modified: Date(),
            kind: "clipboardItem",
            preview: "#ABCDEF"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .color = item.kind { return }
        XCTFail("expected color")
    }

    func testDeriveKindFromTextDefaultsToText() {
        let meta = ClipboardXPCMeta(
            id: "4",
            modified: Date(),
            kind: "clipboardItem",
            preview: "hello world"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .text = item.kind { return }
        XCTFail("expected text")
    }

    func testFilesPreviewYieldsFileKind() {
        let meta = ClipboardXPCMeta(
            id: "5",
            modified: Date(),
            kind: "clipboardItem",
            preview: "(2 files)"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .file = item.kind { return }
        XCTFail("expected file")
    }

    func testClipCardsUseSourceAppAccentForCardAndHeaderTint() {
        XCTAssertTrue(ClipCardAccentPresentation.shouldShowSourceAccent(hasSourceAppIcon: true))
        XCTAssertFalse(ClipCardAccentPresentation.shouldShowSourceAccent(hasSourceAppIcon: false))
        XCTAssertGreaterThanOrEqual(ClipCardAccentPresentation.cardTintOpacity, 0.14)
        XCTAssertGreaterThan(ClipCardAccentPresentation.headerTintOpacity, ClipCardAccentPresentation.cardTintOpacity)
        XCTAssertGreaterThan(ClipCardAccentPresentation.iconStrokeOpacity, 0.3)
        XCTAssertEqual(ClipCardAccentPresentation.topAccentHeight, 0)
        XCTAssertEqual(ClipCardAccentPresentation.dividerAccentOpacity, 0)
    }

    func testClipCardAccentUsesKnownBundleIDForArc() {
        XCTAssertEqual(
            ClipCardAccentPresentation.stableAccentKey(forBundleID: "company.thebrowser.Browser"),
            "purple"
        )
    }

    func testClipCardAccentUsesStablePaletteForGrayscaleIcons() {
        let grayIcon = solidTestIcon(red: 0.18, green: 0.18, blue: 0.18)
        let arcItem = dockItem(bundleID: "company.thebrowser.Browser", icon: grayIcon)
        let chromeItem = dockItem(bundleID: "com.google.Chrome", icon: grayIcon)

        let arcAccent = ClipCardAccentPresentation.accent(for: arcItem)
        let chromeAccent = ClipCardAccentPresentation.accent(for: chromeItem)

        XCTAssertNotEqual(arcAccent, ClipCardAccentPresentation.fallbackAccent)
        XCTAssertNotEqual(chromeAccent, ClipCardAccentPresentation.fallbackAccent)
        XCTAssertNotEqual(arcAccent, chromeAccent)
    }

    func testClipCardAccentHashesUnknownBundleIDs() {
        let grayIcon = solidTestIcon(red: 0.18, green: 0.18, blue: 0.18)
        let first = ClipCardAccentPresentation.accent(for: dockItem(bundleID: "com.example.alpha", icon: grayIcon))
        let second = ClipCardAccentPresentation.accent(for: dockItem(bundleID: "com.example.beta", icon: grayIcon))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            ClipCardAccentPresentation.accent(for: dockItem(bundleID: "com.example.alpha", icon: grayIcon)),
            first
        )
    }

    func testClipCardAccentFallsBackWithoutSourceAppIcon() {
        let meta = ClipboardXPCMeta(
            id: "accent-1",
            modified: Date(),
            kind: "clipboardItem",
            preview: "hello"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        XCTAssertEqual(
            ClipCardAccentPresentation.accent(for: item),
            ClipCardAccentPresentation.fallbackAccent
        )
    }

    func testClipCardAccentUsesDominantColorFromSourceAppIcon() {
        let redIcon = solidTestIcon(red: 0.92, green: 0.12, blue: 0.10)
        let blueIcon = solidTestIcon(red: 0.08, green: 0.40, blue: 0.92)

        XCTAssertNotNil(AppIconColor.dominant(of: redIcon))
        XCTAssertNotNil(AppIconColor.dominant(of: blueIcon))
        XCTAssertNotEqual(AppIconColor.dominant(of: redIcon), AppIconColor.dominant(of: blueIcon))
    }

    private func dockItem(bundleID: String, icon: NSImage) -> DockItem {
        let meta = ClipboardXPCMeta(
            id: "accent-\(bundleID)",
            modified: Date(),
            kind: "clipboardItem",
            preview: "hello"
        )
        let source = SourceApp(bundleID: bundleID, displayName: bundleID, icon: icon)
        return DockItem(from: meta, sourceApp: source, isPinned: false)
    }

    private func solidTestIcon(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    func testDockListTabsKeepAddButtonOutsideTabPill() {
        XCTAssertEqual(DockListTabsPresentation.addButtonPlacement, .outsidePill)
        XCTAssertTrue(DockListTabsPresentation.usesNSItemProviderCompatibleDropTarget)
        XCTAssertTrue(DockListTabsPresentation.inactiveTabsKeepTransparentDropSurface)
        XCTAssertTrue(DockListTabsPresentation.tabDropSurfaceAvoidsNestedButton)
        XCTAssertTrue(DockListTabsPresentation.usesSingleStripDropCoordinator)
        XCTAssertTrue(DockListTabsPresentation.usesAppKitDropBackstop)
        XCTAssertTrue(DockListTabsPresentation.usesPerItemTabDropTarget)
        XCTAssertEqual(DockListTabsPresentation.dropSurfaceActivation, .windowDragOrActiveDrag)
        XCTAssertTrue(DockListTabsPresentation.appKitDropSurfaceFillsTabPill)
        XCTAssertEqual(DockListTabsPresentation.dropTargetPlacement, .stripContent)
        XCTAssertEqual(DockListTabsPresentation.scrollSizing, .flexibleViewport)
        XCTAssertEqual(DockListTabsPresentation.dropTargetLiftStyle, .liftedTab)
        XCTAssertFalse(DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: RecordID.generate()))
        XCTAssertTrue(DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: nil))
        XCTAssertEqual(
            DockListTabsPresentation.pillTabLabels(pinboardNames: [PinnedPinboard.displayName, "Projects"]),
            ["Clipboard History", "Snippets", PinnedPinboard.displayName, "Projects"]
        )
    }

    func testDockCardReorderUsesProviderCompatibleDropTarget() {
        XCTAssertTrue(DockCardReorderPresentation.usesNSItemProviderCompatibleDropTarget)
        XCTAssertTrue(DockCardReorderPresentation.usesAppKitDropBackstop)
        XCTAssertTrue(DockCardReorderPresentation.usesDirectLocalDragGesture)
        XCTAssertTrue(DockCardReorderPresentation.appKitDropSurfaceRequiresNativeCardDrag)
        XCTAssertFalse(DockCardReorderPresentation.usesNativeDragInsideReorderablePinboards)
        XCTAssertTrue(DockCardReorderPresentation.acceptsUTF8PlainTextPayloads)
        XCTAssertEqual(DockCardReorderPresentation.dragPreviewStyle, .compactIcon)
        XCTAssertEqual(DockCardReorderPresentation.trailingDropTargetWidth, 56)
    }

    func testDockCardsUseNeutralFocusRingForSelection() {
        XCTAssertTrue(DockCardShellPresentation.usesNeutralFocusRingForSelection)
        XCTAssertEqual(DockCardShellPresentation.unfocusedBorderWidth, SnippetCardPresentation.unfocusedBorderWidth)
    }

    func testSnippetCardsUseClipboardCardShell() {
        XCTAssertEqual(SnippetCardPresentation.width, DockCardShellPresentation.width)
        XCTAssertEqual(SnippetCardPresentation.height, DockCardShellPresentation.height)
        XCTAssertEqual(SnippetCardPresentation.cornerRadius, DockCardShellPresentation.cornerRadius)
        XCTAssertEqual(SnippetCardPresentation.focusedBorderWidth, DockCardShellPresentation.focusedBorderWidth)
        XCTAssertEqual(SnippetCardPresentation.unfocusedBorderWidth, 1)
        XCTAssertTrue(SnippetCardPresentation.usesClipboardCardBackground)
        XCTAssertTrue(SnippetCardPresentation.usesPersistentUnfocusedBorder)
    }

    func testSnippetEditorUsesInPanelOverlayToAvoidMovingDockPanel() {
        XCTAssertTrue(SnippetEditorPresentation.usesInPanelOverlay)
        XCTAssertFalse(SnippetEditorPresentation.usesNativeWindowSheet)
        XCTAssertTrue(SnippetEditorPresentation.blocksUnderlyingDockContent)
    }

    func testDockCardDropResolverSupportsBeforeAfterAndTrailingAppend() {
        let frames = [
            DockCardDropFrame(itemID: "first", rect: CGRect(x: 16, y: 0, width: 220, height: 240)),
            DockCardDropFrame(itemID: "second", rect: CGRect(x: 248, y: 0, width: 220, height: 240)),
            DockCardDropFrame(itemID: "third", rect: CGRect(x: 480, y: 0, width: 220, height: 240))
        ]

        XCTAssertEqual(
            DockCardDropResolver.reorderTarget(at: CGPoint(x: 40, y: 120), in: frames),
            DockCardReorderTarget(itemID: "first", placement: .before)
        )
        XCTAssertEqual(
            DockCardDropResolver.reorderTarget(at: CGPoint(x: 440, y: 120), in: frames),
            DockCardReorderTarget(itemID: "second", placement: .after)
        )
        XCTAssertEqual(
            DockCardDropResolver.reorderTarget(at: CGPoint(x: 742, y: 120), in: frames),
            DockCardReorderTarget(itemID: "third", placement: .after)
        )
        XCTAssertNil(
            DockCardDropResolver.reorderTarget(at: CGPoint(x: 40, y: 320), in: frames)
        )
    }

    func testDockCardDragStateClearsWhenTabDropCompletes() {
        XCTAssertTrue(
            DockCardDragStatePolicy.shouldClearLocalDrag(
                draggedCardID: "card",
                nativeDraggedCardID: "card",
                activeDraggedItemID: nil,
                isDockDragSurfaceActive: false
            )
        )
        XCTAssertFalse(
            DockCardDragStatePolicy.shouldClearLocalDrag(
                draggedCardID: "card",
                nativeDraggedCardID: "card",
                activeDraggedItemID: "card",
                isDockDragSurfaceActive: true
            )
        )
        XCTAssertFalse(
            DockCardDragStatePolicy.shouldClearLocalDrag(
                draggedCardID: nil,
                nativeDraggedCardID: nil,
                activeDraggedItemID: nil,
                isDockDragSurfaceActive: false
            )
        )
    }

    func testDockCardDimOnlyShowsWhileGlobalDragIsActiveForSameCard() {
        XCTAssertTrue(
            DockCardDragStatePolicy.shouldShowDraggedCardDim(
                cardID: "card",
                draggedCardID: "card",
                activeDraggedItemID: "card",
                isDockDragSurfaceActive: true
            )
        )
        XCTAssertFalse(
            DockCardDragStatePolicy.shouldShowDraggedCardDim(
                cardID: "card",
                draggedCardID: "card",
                activeDraggedItemID: nil,
                isDockDragSurfaceActive: false
            )
        )
        XCTAssertFalse(
            DockCardDragStatePolicy.shouldShowDraggedCardDim(
                cardID: "card",
                draggedCardID: "card",
                activeDraggedItemID: "other",
                isDockDragSurfaceActive: true
            )
        )
    }

    func testDockListDropResolverTargetsPinboardByDragLocation() throws {
        let pinned = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let projects = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000002"))
        let frames = [
            DockListTabDropFrame(selector: .history, rect: CGRect(x: 0, y: 0, width: 120, height: 30)),
            DockListTabDropFrame(selector: .snippets, rect: CGRect(x: 126, y: 0, width: 88, height: 30)),
            DockListTabDropFrame(selector: .pinboard(pinned), rect: CGRect(x: 220, y: 0, width: 78, height: 30)),
            DockListTabDropFrame(selector: .pinboard(projects), rect: CGRect(x: 304, y: 0, width: 96, height: 30))
        ]

        XCTAssertEqual(
            DockListTabDropResolver.targetSelector(at: CGPoint(x: 250, y: 15), in: frames, requiresItemDropTarget: true),
            .pinboard(pinned)
        )
        XCTAssertEqual(
            DockListTabDropResolver.targetSelector(at: CGPoint(x: 350, y: 15), in: frames, requiresItemDropTarget: true),
            .pinboard(projects)
        )
        XCTAssertNil(
            DockListTabDropResolver.targetSelector(at: CGPoint(x: 60, y: 15), in: frames, requiresItemDropTarget: true)
        )
        XCTAssertEqual(
            DockListTabDropResolver.targetSelector(at: CGPoint(x: 250, y: 39), in: frames, requiresItemDropTarget: true),
            .pinboard(pinned)
        )
    }

    func testDockListDropResolverTargetsSnippetsForItemDrag() throws {
        let pinned = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let frames = [
            DockListTabDropFrame(selector: .history, rect: CGRect(x: 0, y: 0, width: 120, height: 30)),
            DockListTabDropFrame(selector: .snippets, rect: CGRect(x: 126, y: 0, width: 88, height: 30)),
            DockListTabDropFrame(selector: .pinboard(pinned), rect: CGRect(x: 220, y: 0, width: 78, height: 30))
        ]

        XCTAssertEqual(
            DockListTabDropResolver.targetSelector(at: CGPoint(x: 160, y: 15), in: frames, requiresItemDropTarget: true),
            .snippets
        )
    }

    func testDockListDropResolverSupportsAppendingAfterLastPinboard() throws {
        let pinned = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let projects = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000002"))
        let frames = [
            DockListTabDropFrame(selector: .history, rect: CGRect(x: 0, y: 0, width: 120, height: 30)),
            DockListTabDropFrame(selector: .snippets, rect: CGRect(x: 126, y: 0, width: 88, height: 30)),
            DockListTabDropFrame(selector: .pinboard(pinned), rect: CGRect(x: 220, y: 0, width: 78, height: 30)),
            DockListTabDropFrame(selector: .pinboard(projects), rect: CGRect(x: 304, y: 0, width: 96, height: 30))
        ]

        XCTAssertEqual(
            DockListTabDropResolver.reorderTarget(at: CGPoint(x: 350, y: 15), in: frames),
            DockListTabReorderTarget(targetID: projects, placement: .before)
        )
        XCTAssertEqual(
            DockListTabDropResolver.reorderTarget(at: CGPoint(x: 392, y: 15), in: frames),
            DockListTabReorderTarget(targetID: projects, placement: .after)
        )
        XCTAssertEqual(
            DockListTabDropResolver.reorderTarget(at: CGPoint(x: 430, y: 15), in: frames),
            DockListTabReorderTarget(targetID: projects, placement: .after)
        )
        XCTAssertNil(
            DockListTabDropResolver.reorderTarget(at: CGPoint(x: 60, y: 15), in: frames)
        )
    }
}
