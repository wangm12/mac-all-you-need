import CoreGraphics
import Foundation

enum BrowserAppleScriptTabReader {
    struct TabPayload: Sendable {
        let index: Int
        let title: String
        let url: String?
        let isActive: Bool
    }

    struct WindowPayload: Sendable {
        let index: Int
        let name: String
        let tabs: [TabPayload]
    }

    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
    ]

    static func isChromium(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return chromiumBundleIDs.contains(bundleIdentifier)
    }

    private static let queueLock = NSLock()
    private static var bundleQueues: [String: DispatchQueue] = [:]

    private static let jxaTimeoutNanoseconds: UInt64 = 3_500_000_000

    private static func jxaQueue(for bundleIdentifier: String) -> DispatchQueue {
        queueLock.lock()
        defer { queueLock.unlock() }
        if let queue = bundleQueues[bundleIdentifier] {
            return queue
        }
        let queue = DispatchQueue(
            label: "com.macallyouneed.windowhub.jxa.\(bundleIdentifier)",
            qos: .userInitiated
        )
        bundleQueues[bundleIdentifier] = queue
        return queue
    }

    static func fetchWindows(bundleIdentifier: String) -> [WindowPayload] {
        guard chromiumBundleIDs.contains(bundleIdentifier) else { return [] }
        if BrowserAppleScriptTabCache.isAccessDenied(for: bundleIdentifier) { return [] }
        return jxaQueue(for: bundleIdentifier).sync {
            fetchWindowsOnJXAQueue(bundleIdentifier: bundleIdentifier)
        }
    }

    private static func fetchWindowsOnJXAQueue(bundleIdentifier: String) -> [WindowPayload] {
        let source = """
        function run() {
          const app = Application('\(bundleIdentifier)');
          const windows = app.windows();
          const payload = windows.map(function(w, wi) {
            const active = w.activeTabIndex();
            const tabs = w.tabs().map(function(t, ti) {
              return {
                index: ti + 1,
                title: String(t.title()),
                url: String(t.url()),
                active: (ti + 1) === active
              };
            });
            return { index: wi + 1, name: String(w.name()), tabs: tabs };
          });
          return JSON.stringify(payload);
        }
        """
        guard let json = runJXA(source, bundleIdentifier: bundleIdentifier),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WindowPayloadDTO].self, from: data)
        else { return [] }

        return decoded.map { window in
            WindowPayload(
                index: window.index,
                name: window.name,
                tabs: window.tabs.map { tab in
                    TabPayload(
                        index: tab.index,
                        title: tab.title,
                        url: tab.url?.isEmpty == true ? nil : tab.url,
                        isActive: tab.active
                    )
                }
            )
        }
    }

    static func activateTab(bundleIdentifier: String, windowIndex: Int, tabIndex: Int) -> Bool {
        guard chromiumBundleIDs.contains(bundleIdentifier) else { return false }
        if BrowserAppleScriptTabCache.isAccessDenied(for: bundleIdentifier) { return false }
        let source = """
        function run() {
          const app = Application('\(bundleIdentifier)');
          app.activate();
          const wins = app.windows();
          if (wins.length < \(windowIndex)) return false;
          const win = wins[\(windowIndex - 1)];
          win.index = 1;
          win.activeTabIndex = \(tabIndex);
          return true;
        }
        """
        return jxaQueue(for: bundleIdentifier).sync {
            runJXA(source, bundleIdentifier: bundleIdentifier) != nil
        }
    }

    static func activateWindow(bundleIdentifier: String, windowIndex: Int) -> Bool {
        guard chromiumBundleIDs.contains(bundleIdentifier) else { return false }
        if BrowserAppleScriptTabCache.isAccessDenied(for: bundleIdentifier) { return false }
        let source = """
        function run() {
          const app = Application('\(bundleIdentifier)');
          app.activate();
          const wins = app.windows();
          if (wins.length < \(windowIndex)) return false;
          const win = wins[\(windowIndex - 1)];
          win.index = 1;
          return true;
        }
        """
        return jxaQueue(for: bundleIdentifier).sync {
            runJXA(source, bundleIdentifier: bundleIdentifier) != nil
        }
    }

    static func displayTitle(title: String, url: String?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard let url, !url.isEmpty, let parsed = URL(string: url) else {
            return "New Tab"
        }
        if let host = parsed.host, !host.isEmpty {
            let path = parsed.path
            if path.isEmpty || path == "/" { return host }
            return "\(host)\(path)"
        }
        return url
    }

    static func domain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host else { return nil }
        return host
    }

    private struct WindowPayloadDTO: Decodable {
        let index: Int
        let name: String
        let tabs: [TabPayloadDTO]
    }

    private struct TabPayloadDTO: Decodable {
        let index: Int
        let title: String
        let url: String?
        let active: Bool
    }

    private static func runJXA(_ source: String, bundleIdentifier: String? = nil) -> String? {
        if let bundleIdentifier, BrowserAppleScriptTabCache.isAccessDenied(for: bundleIdentifier) {
            return nil
        }

        final class OutputBox: @unchecked Sendable {
            var value: String?
            var terminationStatus: Int32 = -1
            var errorText = ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", source]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        let box = OutputBox()
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }
            do {
                try process.run()
            } catch {
                if let bundleIdentifier {
                    BrowserAppleScriptTabCache.recordAccessFailure(for: bundleIdentifier)
                }
                return
            }
            process.waitUntilExit()
            box.terminationStatus = process.terminationStatus
            box.errorText = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            box.value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let timedOut = finished.wait(timeout: .now() + .nanoseconds(Int(jxaTimeoutNanoseconds))) == .timedOut
        if timedOut {
            if process.isRunning {
                process.terminate()
            }
            _ = finished.wait(timeout: .now() + .seconds(1))
            if let bundleIdentifier {
                BrowserAppleScriptTabCache.recordAccessFailure(for: bundleIdentifier)
            }
            return nil
        }

        guard box.terminationStatus == 0 else {
            if let bundleIdentifier {
                if BrowserAppleScriptTabCache.looksLikeAccessDenied(box.errorText) {
                    BrowserAppleScriptTabCache.recordAccessDenied(for: bundleIdentifier)
                } else {
                    BrowserAppleScriptTabCache.recordAccessFailure(for: bundleIdentifier)
                }
            }
            return nil
        }

        guard let output = box.value, !output.isEmpty else { return nil }
        return output
    }
}

enum BrowserAppleScriptTabCache {
    struct WindowProbe: Sendable {
        let windowID: CGWindowID
        let title: String
        let usesAppElement: Bool
        let tabCount: Int?
    }

    private struct Entry {
        let fetchedAt: Date
        let windows: [BrowserAppleScriptTabReader.WindowPayload]
        var assignments: [CGWindowID: Int] = [:]
        var axTabCounts: [CGWindowID: Int] = [:]
    }

    private static let lock = NSLock()
    private static var entries: [pid_t: Entry] = [:]
    private static var deniedBundleIDs: Set<String> = []
    private static var failedBundleIDs: Set<String> = []
    private static let jxaCacheTTL: TimeInterval = 60.0
    private static let failureBackoff: TimeInterval = 30.0
    private static var failureRecordedAt: [String: Date] = [:]

    static func isAccessDenied(for bundleIdentifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if deniedBundleIDs.contains(bundleIdentifier) { return true }
        if failedBundleIDs.contains(bundleIdentifier),
           let recordedAt = failureRecordedAt[bundleIdentifier],
           Date().timeIntervalSince(recordedAt) < failureBackoff
        {
            return true
        }
        return false
    }

    static func recordAccessDenied(for bundleIdentifier: String) {
        lock.lock()
        deniedBundleIDs.insert(bundleIdentifier)
        lock.unlock()
    }

    static func recordAccessFailure(for bundleIdentifier: String) {
        lock.lock()
        failedBundleIDs.insert(bundleIdentifier)
        failureRecordedAt[bundleIdentifier] = Date()
        lock.unlock()
    }

    static func looksLikeAccessDenied(_ errorText: String) -> Bool {
        let lowered = errorText.lowercased()
        return lowered.contains("not authorized")
            || lowered.contains("not allowed")
            || lowered.contains("access for assistive")
            || lowered.contains("application isn’t running")
            || lowered.contains("application isn't running")
    }

    static func resetAccessState(for bundleIdentifier: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let bundleIdentifier {
            deniedBundleIDs.remove(bundleIdentifier)
            failedBundleIDs.remove(bundleIdentifier)
            failureRecordedAt.removeValue(forKey: bundleIdentifier)
        } else {
            deniedBundleIDs.removeAll()
            failedBundleIDs.removeAll()
            failureRecordedAt.removeAll()
        }
    }

    /// Clears transient JXA failures so the next panel open can retry without
    /// waiting out the backoff window. Permanent Automation denials are kept.
    static func resetTransientFailures() {
        lock.lock()
        defer { lock.unlock() }
        failedBundleIDs.removeAll()
        failureRecordedAt.removeAll()
    }

    static func evict(pid: pid_t) {
        lock.lock()
        entries.removeValue(forKey: pid)
        lock.unlock()
    }

    #if DEBUG
    static func _testSeedWindows(pid: pid_t, windows: [BrowserAppleScriptTabReader.WindowPayload]) {
        lock.lock()
        entries[pid] = Entry(fetchedAt: Date(), windows: windows)
        lock.unlock()
    }
    #endif

    static func rememberAXTabCount(pid: pid_t, windowID: CGWindowID, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        if var entry = entries[pid] {
            entry.axTabCounts[windowID] = count
            entries[pid] = entry
        } else {
            entries[pid] = Entry(fetchedAt: .distantPast, windows: [], axTabCounts: [windowID: count])
        }
        lock.unlock()
    }

    static func axTabCount(pid: pid_t, windowID: CGWindowID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return entries[pid]?.axTabCounts[windowID]
    }

    /// Clears per-window assignments so a new snapshot gets fresh Chrome window matching.
    static func beginSnapshot(pid: pid_t, bundleIdentifier: String, forceRefresh: Bool = false) {
        lock.lock()
        if !forceRefresh,
           var entry = entries[pid],
           Date().timeIntervalSince(entry.fetchedAt) < jxaCacheTTL
        {
            entry.assignments = [:]
            entries[pid] = entry
            lock.unlock()
            return
        }
        lock.unlock()

        let windows = BrowserAppleScriptTabReader.fetchWindows(bundleIdentifier: bundleIdentifier)

        lock.lock()
        entries[pid] = Entry(fetchedAt: Date(), windows: windows, assignments: [:])
        lock.unlock()
    }

    static func windows(pid: pid_t, bundleIdentifier: String) -> [BrowserAppleScriptTabReader.WindowPayload] {
        lock.lock()
        if let entry = entries[pid], Date().timeIntervalSince(entry.fetchedAt) < jxaCacheTTL {
            let cached = entry.windows
            lock.unlock()
            return cached
        }
        lock.unlock()

        let windows = BrowserAppleScriptTabReader.fetchWindows(bundleIdentifier: bundleIdentifier)

        lock.lock()
        entries[pid] = Entry(fetchedAt: Date(), windows: windows)
        lock.unlock()
        return windows
    }

    static func assignedWindowIndex(pid: pid_t, windowID: CGWindowID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return entries[pid]?.assignments[windowID]
    }

    static func assignAllWindows(
        pid: pid_t,
        probes: [WindowProbe]
    ) -> [CGWindowID: Int] {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[pid] else { return [:] }

        var assignments: [CGWindowID: Int] = [:]
        var usedScript = Set<Int>()
        let sortedProbes = probes.sorted { $0.windowID < $1.windowID }

        for probe in sortedProbes {
            guard let match = entry.windows.first(where: { window in
                !usedScript.contains(window.index) && namesMatch(probe.title, window.name)
            }) else { continue }
            assignments[probe.windowID] = match.index
            usedScript.insert(match.index)
        }

        for probe in sortedProbes where assignments[probe.windowID] == nil {
            guard let tabCount = probe.tabCount ?? entry.axTabCounts[probe.windowID], tabCount > 0 else {
                continue
            }
            guard let match = entry.windows.first(where: { window in
                !usedScript.contains(window.index) && window.tabs.count == tabCount
            }) else { continue }
            assignments[probe.windowID] = match.index
            usedScript.insert(match.index)
        }

        for probe in sortedProbes where assignments[probe.windowID] == nil {
            guard let match = entry.windows.first(where: { window in
                !usedScript.contains(window.index) && activeTabTitleMatch(probe.title, window: window)
            }) else { continue }
            assignments[probe.windowID] = match.index
            usedScript.insert(match.index)
        }

        for probe in sortedProbes where assignments[probe.windowID] == nil {
            guard let match = entry.windows.first(where: { !usedScript.contains($0.index) }) else { continue }
            assignments[probe.windowID] = match.index
            usedScript.insert(match.index)
        }

        entry.assignments = assignments
        entries[pid] = entry
        return assignments
    }

    static func probes(
        windowIndex: Int,
        scriptWindows: [BrowserAppleScriptTabReader.WindowPayload]
    ) -> [WindowHubTabProbe] {
        guard let scriptWindow = scriptWindows.first(where: { $0.index == windowIndex }) else {
            return []
        }
        return scriptWindow.tabs.map { tab in
            WindowHubTabProbe(
                key: "as:\(windowIndex):\(tab.index)",
                title: BrowserAppleScriptTabReader.displayTitle(title: tab.title, url: tab.url),
                domain: BrowserAppleScriptTabReader.domain(from: tab.url),
                isActive: tab.isActive,
                isPinned: false,
                isAudible: false,
                isPrivate: tab.title.localizedCaseInsensitiveContains("private"),
                axElement: nil
            )
        }
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a != "Window", b != "Window" else { return false }
        if a.compare(b, options: .caseInsensitive) == .orderedSame { return true }
        return a.localizedCaseInsensitiveContains(b) || b.localizedCaseInsensitiveContains(a)
    }

    static func activeTabTitleMatch(
        _ probeTitle: String,
        window: BrowserAppleScriptTabReader.WindowPayload
    ) -> Bool {
        guard let active = window.tabs.first(where: \.isActive) else { return false }
        let display = BrowserAppleScriptTabReader.displayTitle(title: active.title, url: active.url)
        return namesMatch(probeTitle, display) || namesMatch(probeTitle, active.title)
    }
}
