import SwiftUI

struct MAYNListPaginationState: Equatable {
    let currentPage: Int
    let totalPages: Int
    let totalItems: Int
    let pageSize: Int

    var canGoFirst: Bool { currentPage > 0 }
    var canGoPrevious: Bool { canGoFirst }
    var canGoNext: Bool { currentPage < totalPages - 1 }
    var canGoLast: Bool { canGoNext }

    func rangeText(visibleItemCount: Int) -> String {
        guard totalItems > 0 else { return "0 of 0" }
        let start = currentPage * pageSize + 1
        let end = min(start + max(visibleItemCount, 1) - 1, totalItems)
        return "\(start)-\(end) of \(totalItems)"
    }
}

enum MAYNListPagination {
    static func make(totalItems: Int, requestedPage: Int, pageSize requestedPageSize: Int) -> MAYNListPaginationState {
        let pageSize = max(1, requestedPageSize)
        let totalPages = max(1, Int(ceil(Double(totalItems) / Double(pageSize))))
        let currentPage = min(max(0, requestedPage), totalPages - 1)
        return MAYNListPaginationState(
            currentPage: currentPage,
            totalPages: totalPages,
            totalItems: totalItems,
            pageSize: pageSize
        )
    }

    static func slice<Item>(_ items: [Item], pagination: MAYNListPaginationState) -> [Item] {
        let start = pagination.currentPage * pagination.pageSize
        let end = min(start + pagination.pageSize, items.count)
        guard start < end else { return [] }
        return Array(items[start ..< end])
    }

    static func clampedPageIndex(oneBasedPage: Int, totalPages: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        return min(max(0, oneBasedPage - 1), totalPages - 1)
    }

    static func parseJumpText(_ text: String, totalPages: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmed), pageNumber >= 1 else { return nil }
        return clampedPageIndex(oneBasedPage: pageNumber, totalPages: totalPages)
    }
}

struct MAYNListPaginationFooter: View {
    let state: MAYNListPaginationState
    let visibleItemCount: Int
    var showsNavigation = true
    let goToPage: (Int) -> Void

    @State private var pageJumpText = ""

    private var rangeText: String {
        state.rangeText(visibleItemCount: visibleItemCount)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsNavigation, state.totalPages > 1 {
                Spacer(minLength: 12)

                paginationControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncPageJumpText() }
        .onChange(of: state.currentPage) { _, _ in syncPageJumpText() }
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            paginationIconButton(
                systemImage: "chevron.backward.to.line",
                label: "First page",
                enabled: state.canGoFirst
            ) {
                goToPage(0)
            }

            paginationIconButton(
                systemImage: "chevron.left",
                label: "Previous page",
                enabled: state.canGoPrevious
            ) {
                goToPage(state.currentPage - 1)
            }

            HStack(spacing: 6) {
                Text("Page")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MAYNTextField(
                    placeholder: "",
                    text: $pageJumpText,
                    width: 52,
                    alignment: .center
                )
                .onSubmit(commitPageJump)

                Text("of \(state.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .leading)
            }

            paginationIconButton(
                systemImage: "chevron.right",
                label: "Next page",
                enabled: state.canGoNext
            ) {
                goToPage(state.currentPage + 1)
            }

            paginationIconButton(
                systemImage: "chevron.forward.to.line",
                label: "Last page",
                enabled: state.canGoLast
            ) {
                goToPage(state.totalPages - 1)
            }
        }
    }

    private func paginationIconButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        MAYNButton(role: .secondary, height: MAYNControlMetrics.controlHeight, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14)
        }
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func syncPageJumpText() {
        pageJumpText = "\(state.currentPage + 1)"
    }

    private func commitPageJump() {
        guard let page = MAYNListPagination.parseJumpText(pageJumpText, totalPages: state.totalPages) else {
            syncPageJumpText()
            return
        }
        goToPage(page)
        syncPageJumpText()
    }
}
