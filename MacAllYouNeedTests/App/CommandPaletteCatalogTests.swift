@testable import MacAllYouNeed
import XCTest

final class CommandPaletteCatalogTests: XCTestCase {
    private var allEnabled: Set<MainAppDestination> {
        Set(MainAppDestination.primarySidebarDestinations + [.settings])
    }

    private func context(
        destination: MainAppDestination = .voice,
        failedDownloadCount: Int = 0,
        enabledDestinations: Set<MainAppDestination>? = nil,
        attention: CommandPaletteAttentionSnapshot? = nil
    ) -> CommandPaletteContext {
        CommandPaletteContext(
            destination: destination,
            hotkeys: [:],
            voiceShortcut: "⌥Space",
            voiceMode: .toggle,
            failedDownloadCount: failedDownloadCount,
            enabledDestinations: enabledDestinations ?? allEnabled,
            attention: attention ?? CommandPaletteAttentionSnapshot(
                failedDownloadCount: failedDownloadCount,
                orphanCacheCount: 0,
                missingPermissions: [],
                permissionsAttentionTitle: nil,
                voiceSetupNeeded: false
            )
        )
    }

    private var voiceItems: [CommandPaletteAction] {
        CommandPaletteCatalog.flatItems(from: CommandPaletteCatalog.sections(context: context()))
    }

    func testFilterReturnsAllActionsForEmptyQuery() {
        XCTAssertEqual(
            CommandPaletteCatalog.filter(voiceItems, query: ""),
            voiceItems
        )
        XCTAssertEqual(
            CommandPaletteCatalog.filter(voiceItems, query: "   "),
            voiceItems
        )
    }

    func testFilterMatchesTitleCaseInsensitively() {
        let results = CommandPaletteCatalog.filter(voiceItems, query: "clipboard")
        XCTAssertTrue(results.contains(where: { $0.id == "nav-clipboard" }))
    }

    func testFilterMatchesSubtitle() {
        let actions = [
            CommandPaletteAction(
                id: "x",
                title: "Run",
                subtitle: "Downloads queue",
                symbolName: "arrow.down.circle",
                section: .currentContext,
                kind: .reviewFailedDownloads
            ),
        ]
        XCTAssertEqual(CommandPaletteCatalog.filter(actions, query: "downloads").map(\.id), ["x"])
    }

    func testFilterReturnsEmptyWhenNothingMatches() {
        XCTAssertTrue(CommandPaletteCatalog.filter(voiceItems, query: "zzzz").isEmpty)
    }

    func testCatalogIncludesPrimaryDestinations() {
        let titles = Set(voiceItems.map(\.title))
        XCTAssertTrue(titles.contains("Dashboard"))
        XCTAssertTrue(titles.contains("Clipboard"))
        XCTAssertTrue(titles.contains("Settings"))
        XCTAssertTrue(titles.contains("AI File Organizer"))
        XCTAssertTrue(titles.contains("Window Layouts"))
        XCTAssertTrue(titles.contains("Windows Hub"))
        XCTAssertFalse(titles.contains("Open Dashboard"))
    }

    func testCatalogIncludesContextualVoiceActions() {
        let titles = Set(voiceItems.map(\.title))
        XCTAssertTrue(titles.contains("Start dictation"))
        XCTAssertTrue(titles.contains("Open transcript history"))
        XCTAssertTrue(titles.contains("Open Voice settings"))
    }

    func testCatalogOrdersCurrentContextBeforeNavigation() {
        let sections = CommandPaletteCatalog.sections(context: context())
        XCTAssertEqual(sections.first?.section, .currentContext)
        XCTAssertTrue(sections.contains(where: { $0.section == .navigation }))
        if let navigationIndex = sections.firstIndex(where: { $0.section == .navigation }),
           let contextIndex = sections.firstIndex(where: { $0.section == .currentContext }) {
            XCTAssertLessThan(contextIndex, navigationIndex)
        }
    }

    func testClipboardContextPrioritizesClipboardActions() {
        let sections = CommandPaletteCatalog.sections(context: context(destination: .clipboard))
        XCTAssertEqual(sections.first?.section, .currentContext)
        let titles = Set(sections.first?.items.map(\.title) ?? [])
        XCTAssertTrue(titles.contains("Search clipboard history"))
        XCTAssertTrue(titles.contains("Open snippet library"))
    }

    func testCatalogIncludesAttentionSectionWhenDownloadsFailed() {
        let sections = CommandPaletteCatalog.sections(
            context: context(failedDownloadCount: 4)
        )
        XCTAssertTrue(sections.contains(where: { $0.section == .attention }))
        let attentionItems = sections.first(where: { $0.section == .attention })?.items ?? []
        XCTAssertEqual(attentionItems.first?.title, "Review 4 downloads needing attention")
    }

    func testCatalogOmitsDisabledFeatureActions() {
        let enabled: Set<MainAppDestination> = [.dashboard, .settings]
        let items = CommandPaletteCatalog.flatItems(
            from: CommandPaletteCatalog.sections(context: context(enabledDestinations: enabled))
        )
        XCTAssertFalse(items.contains(where: { $0.kind == .startDictation }))
        XCTAssertFalse(items.contains(where: { $0.id == "nav-voice" }))
        XCTAssertTrue(items.contains(where: { $0.id == "nav-dashboard" }))
    }

    func testFilteredSectionsCollapseToFlatListWhenQueryPresent() {
        let sections = CommandPaletteCatalog.sections(context: context())
        let filtered = CommandPaletteCatalog.filteredSections(sections, query: "voice")
        XCTAssertTrue(filtered.isFiltering)
        XCTAssertEqual(filtered.sections.count, 1)
        XCTAssertTrue(filtered.sections[0].items.allSatisfy {
            $0.title.lowercased().contains("voice")
                || ($0.subtitle?.lowercased().contains("voice") ?? false)
        })
    }
}
