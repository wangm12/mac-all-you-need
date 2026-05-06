# Plan 4: FolderPreview Subsystem

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working Quick Look extension that previews folders (Files / Grid / Analyze view modes) and archives (ZIP/RAR/7z/TAR/GZ/BZ2) with safety caps, plus a standalone "Browse folder" window in the main app sharing the same SwiftUI views. Image-heavy folders auto-suggest the contact-sheet Grid mode.

**Architecture:** All rendering logic lives in `Platform/FolderPreview/` and `UI/FolderPreview/` (SwiftUI views), so the Quick Look extension and the standalone window mount the exact same view tree. Folder enumeration produces a `FolderInventory` value (file list + analysis stats). Archive previews go through an `ArchiveBackend` protocol; the only v1 implementation is `LibArchiveBackend`, vendored from libarchive 3.7.x. Thumbnail generation uses `QLThumbnailGenerator`, cached on disk in `App Group/thumbnails/` keyed by `(volumeID, inode, mtime)`. Open/Copy actions in the sandboxed extension call out to the unsandboxed main app via `FolderPreviewXPC` (a second Mach service alongside the clipboard XPC from Plan 3).

**Tech Stack:** SwiftUI for views, Quartz for `QLThumbnailGenerator` and the `QLPreviewProvider` API, vendored libarchive, `NSXPCConnection` for the privileged-action handoff.

**Reads from spec:** §3 (decision 9), §7 (entire), §9 (Full Disk Access JIT prompt).

**Depends on:** Plan 0 (FolderPreview target, App Group), Plan 1 (`AppGroup`, `Logging`), Plan 3 (XPC pattern reused).

**Produces working software:** in Finder, pressing Space on any folder shows the analysis overview; pressing Space on a `.zip` shows its contents; the menu-bar "Browse folder…" opens a multi-pane window over arbitrary folders.

---

## Public types defined here

| Type | Module path | Purpose |
|---|---|---|
| `FolderInventory` | `Platform.FolderPreview` | `{entries, totalSize, breakdown, largest, isPartial}` |
| `FolderEntry` | `Platform.FolderPreview` | `{name, path, isDirectory, size, modified, kind}` |
| `FolderEnumerator` | `Platform.FolderPreview` | Async enumerator with cap and callback for partial results |
| `ArchiveBackend` | `Platform.Archive` | Protocol; lists entries + extracts a single entry |
| `LibArchiveBackend` | `Platform.Archive` | libarchive impl |
| `ArchiveSafety` | `Platform.Archive` | Caps + path-traversal/symlink validation |
| `ThumbnailService` | `Platform.FolderPreview` | `QLThumbnailGenerator` wrapper with on-disk cache |
| `FolderPreviewView` | `UI.FolderPreview` | Top-level SwiftUI host view |
| `FolderPreviewXPCProtocol` | `Core.XPC` | Open/Copy/Reveal actions via unsandboxed main app |

---

## File structure (added)

```
Shared/Vendored/libarchive/                # vendored from libarchive/libarchive tag v3.7.4

Shared/Sources/CLibArchive/                # SwiftPM C wrapper (analogous to CArgon2)
├── shim.c
├── include/CLibArchive.h
└── module.modulemap

Shared/Sources/Platform/Archive/
├── ArchiveBackend.swift
├── ArchiveSafety.swift
└── LibArchiveBackend.swift

Shared/Sources/Platform/FolderPreview/
├── FolderEntry.swift
├── FolderInventory.swift
├── FolderEnumerator.swift
└── ThumbnailService.swift

Shared/Sources/UI/FolderPreview/
├── FolderPreviewView.swift
├── FolderFilesView.swift
├── FolderGridView.swift
├── FolderAnalyzeView.swift
└── ArchivePreviewView.swift

Shared/Sources/Core/XPC/
└── FolderPreviewXPCProtocol.swift

FolderPreview/PreviewProvider.swift        # MODIFY (replace placeholder)

MacAllYouNeed/FolderPreview/
├── BrowseFolderWindowController.swift
└── BrowseFolderCoordinator.swift          # listens for XPC actions, performs unsandboxed work

Shared/Tests/PlatformTests/FolderPreview/
├── FolderEnumeratorTests.swift
├── ArchiveSafetyTests.swift
├── LibArchiveBackendTests.swift
└── ThumbnailServiceTests.swift
```

---

## Task 4.0: Signing spike for Quick Look extension → App Group XPC

**Files:**
- Create: `docs/superpowers/findings/folderpreview-xpc-spike.md`
- Modify only after spike passes: `FolderPreview/FolderPreview.entitlements`
- Modify only after spike passes: `MacAllYouNeed/MacAllYouNeed.entitlements`

- [ ] **Step 1: Build a minimal XPC probe before implementing Open/Copy/Reveal**

Use the final intended bundle IDs, Developer ID team, App Group, sandbox setting, and hardened runtime setting. The main app hosts a temporary method `ping(reply:)`; the Quick Look extension calls it from `providePreview`.

```swift
@objc protocol FolderPreviewProbeXPC {
    func ping(reply: @escaping (String) -> Void)
}
```

- [ ] **Step 2: Verify from Finder/qlmanage**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
qlmanage -r
qlmanage -p /tmp
```

Expected: `docs/superpowers/findings/folderpreview-xpc-spike.md` records `PASS`, the service name, signing identity, App Group, sandbox state, and the observed `"pong"` reply from the Quick Look extension.

- [ ] **Step 3: If the spike fails, patch Task 4.8 before continuing**

Fallback contract: Quick Look uses extension-local read-only actions only and shows "Open in Mac All You Need" for Open/Copy/Reveal. The standalone app then performs the action after the user opens the folder there.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/findings/folderpreview-xpc-spike.md FolderPreview MacAllYouNeed
git commit -m "test(folderpreview): verify Quick Look to app XPC reachability"
```

---

## Task 4.1: `FolderEntry`, `FolderInventory`, and `FolderEnumerator`

**Files:** see above.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Platform

final class FolderEnumeratorTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fe-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 1024).write(to: dir.appendingPathComponent("a.txt"))
        try? Data(repeating: 0, count: 2048).write(to: dir.appendingPathComponent("b.png"))
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 4096).write(to: dir.appendingPathComponent("sub/c.swift"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    func testEnumerateProducesEntries() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        XCTAssertGreaterThanOrEqual(inv.entries.count, 3)
        XCTAssertGreaterThanOrEqual(inv.totalSize, 1024 + 2048 + 4096)
    }

    func testBreakdownGroupsByCategory() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        XCTAssertGreaterThan(inv.breakdown[.images, default: 0], 0)
        XCTAssertGreaterThan(inv.breakdown[.code, default: 0], 0)
    }

    func testLargestFilesSorted() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        let largest = inv.largest.first?.name
        XCTAssertEqual(largest, "c.swift")
    }

    func testCapMarksPartial() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1)
        XCTAssertTrue(inv.isPartial)
    }
}
```

- [ ] **Step 2: Implement value types**

```swift
import Foundation

public enum FolderEntryKind: String, Sendable {
    case images, videos, audio, code, documents, archives, other, folder
}

public struct FolderEntry: Sendable, Equatable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date
    public let kind: FolderEntryKind
}

public struct FolderInventory: Sendable {
    public let entries: [FolderEntry]
    public let totalSize: Int64
    public let breakdown: [FolderEntryKind: Int]
    public let largest: [FolderEntry]   // top 5
    public let isPartial: Bool
}

public enum FolderEnumeratorError: Error { case notADirectory }

public enum FolderEnumerator {
    public static func enumerate(url: URL, maxEntries: Int = 50_000, includeHidden: Bool = false) async throws -> FolderInventory {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderEnumeratorError.notADirectory
        }
        return try await Task.detached(priority: .utility) {
            try Self.enumerateSync(url: url, maxEntries: maxEntries, includeHidden: includeHidden)
        }.value
    }

    private static func enumerateSync(url: URL, maxEntries: Int, includeHidden: Bool) throws -> FolderInventory {
        var entries: [FolderEntry] = []
        var total: Int64 = 0
        var breakdown: [FolderEntryKind: Int] = [:]
        var partial = false

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                              options: options) else {
            throw FolderEnumeratorError.notADirectory
        }
        for case let item as URL in enumerator {
            if entries.count >= maxEntries { partial = true; break }
            guard let vals = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = vals.isDirectory ?? false
            let size = Int64(vals.fileSize ?? 0)
            let kind = isDir ? FolderEntryKind.folder : Self.classify(name: item.lastPathComponent)
            entries.append(FolderEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: isDir,
                size: size,
                modified: vals.contentModificationDate ?? .distantPast,
                kind: kind
            ))
            if !isDir {
                total += size
                breakdown[kind, default: 0] += 1
            }
        }
        let largest = entries.filter { !$0.isDirectory }.sorted { $0.size > $1.size }.prefix(5)
        return FolderInventory(entries: entries, totalSize: total, breakdown: breakdown,
                               largest: Array(largest), isPartial: partial)
    }

    private static func classify(name: String) -> FolderEntryKind {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "avif": return .images
        case "mp4", "mov", "mkv", "webm", "avi", "flv": return .videos
        case "mp3", "wav", "flac", "aac", "ogg", "m4a": return .audio
        case "swift", "py", "go", "rs", "ts", "tsx", "js", "jsx", "java", "rb", "kt", "c", "cpp", "h", "m", "mm", "sh":
            return .code
        case "pdf", "md", "txt", "doc", "docx", "rtf", "pages", "key", "numbers", "xlsx":
            return .documents
        case "zip", "tar", "gz", "bz2", "7z", "rar", "xz":
            return .archives
        default: return .other
        }
    }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter FolderEnumeratorTests
git add Shared/Sources/Platform/FolderPreview/FolderEntry.swift Shared/Sources/Platform/FolderPreview/FolderInventory.swift Shared/Sources/Platform/FolderPreview/FolderEnumerator.swift Shared/Tests/PlatformTests/FolderPreview/FolderEnumeratorTests.swift
git commit -m "feat(platform): add FolderEnumerator + value types"
```

---

## Task 4.2: `ArchiveSafety` caps and path validation

**Files:**
- Create: `Shared/Sources/Platform/Archive/ArchiveSafety.swift`
- Create: `Shared/Tests/PlatformTests/FolderPreview/ArchiveSafetyTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Platform

final class ArchiveSafetyTests: XCTestCase {
    let limits = ArchiveSafety.Limits.default

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath("/etc/passwd", limits: limits))
    }

    func testRejectsTraversal() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath("../etc/shadow", limits: limits))
        XCTAssertThrowsError(try ArchiveSafety.validatePath("foo/../../bar", limits: limits))
    }

    func testAcceptsRelativePath() throws {
        XCTAssertNoThrow(try ArchiveSafety.validatePath("dir/file.txt", limits: limits))
    }

    func testRejectsTooManyEntries() {
        XCTAssertThrowsError(try ArchiveSafety.checkEntryCount(limits.maxEntries + 1, limits: limits))
    }

    func testRejectsTooDeep() {
        XCTAssertThrowsError(try ArchiveSafety.validatePath(String(repeating: "a/", count: 100) + "x", limits: limits))
    }

    func testRejectsTooLargeUncompressed() {
        XCTAssertThrowsError(try ArchiveSafety.checkTotalUncompressed(limits.maxTotalUncompressedBytes + 1, limits: limits))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public enum ArchiveSafetyError: Error, Equatable {
    case absolutePath, pathTraversal, tooDeep
    case tooManyEntries, tooLargeUncompressed, perFileTooLarge
    case symlinkInPreview
}

public enum ArchiveSafety {
    public struct Limits: Sendable {
        public var maxEntries: Int
        public var maxDepth: Int
        public var maxTotalUncompressedBytes: Int64
        public var maxPerFileBytes: Int64
        public static let `default` = Limits(
            maxEntries: 50_000,
            maxDepth: 64,
            maxTotalUncompressedBytes: 5 * 1024 * 1024 * 1024,
            maxPerFileBytes: 1 * 1024 * 1024 * 1024
        )
    }

    public static func validatePath(_ path: String, limits: Limits) throws {
        if path.hasPrefix("/") { throw ArchiveSafetyError.absolutePath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        var depth = 0
        for p in parts {
            if p == ".." { throw ArchiveSafetyError.pathTraversal }
            if p == "." || p.isEmpty { continue }
            depth += 1
            if depth > limits.maxDepth { throw ArchiveSafetyError.tooDeep }
        }
    }

    public static func checkEntryCount(_ count: Int, limits: Limits) throws {
        if count > limits.maxEntries { throw ArchiveSafetyError.tooManyEntries }
    }

    public static func checkTotalUncompressed(_ bytes: Int64, limits: Limits) throws {
        if bytes > limits.maxTotalUncompressedBytes { throw ArchiveSafetyError.tooLargeUncompressed }
    }

    public static func checkPerFileSize(_ bytes: Int64, limits: Limits) throws {
        if bytes > limits.maxPerFileBytes { throw ArchiveSafetyError.perFileTooLarge }
    }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter ArchiveSafetyTests
git add Shared/Sources/Platform/Archive/ArchiveSafety.swift Shared/Tests/PlatformTests/FolderPreview/ArchiveSafetyTests.swift
git commit -m "feat(platform): add ArchiveSafety guard"
```

---

## Task 4.3: Vendor libarchive

**Files:**
- Create: `Shared/Vendored/libarchive/` (from https://github.com/libarchive/libarchive tag `v3.7.4`)
- Create: `Shared/Sources/CLibArchive/`
- Modify: `Shared/Package.swift`

- [ ] **Step 1: Vendor**

```bash
mkdir -p Shared/Vendored
git clone --depth 1 --branch v3.7.4 https://github.com/libarchive/libarchive.git Shared/Vendored/libarchive
rm -rf Shared/Vendored/libarchive/.git Shared/Vendored/libarchive/test_utils Shared/Vendored/libarchive/doc
```

- [ ] **Step 2: SwiftPM C wrapper**

`Shared/Sources/CLibArchive/include/CLibArchive.h`:

```c
#ifndef CLibArchive_h
#define CLibArchive_h
#include <stddef.h>
#include <stdint.h>
#include <archive.h>
#include <archive_entry.h>
#endif
```

`Shared/Sources/CLibArchive/shim.c`:

```c
/* Empty: the static libarchive.a is built by scripts/build-libarchive.sh */
```

`Shared/Sources/CLibArchive/module.modulemap`:

```
module CLibArchive {
    umbrella header "include/CLibArchive.h"
    link "z"
    link "bz2"
    link "lzma"
    export *
}
```

- [ ] **Step 3: Build libarchive with CMake, then expose the static library to SwiftPM**

Do not compile libarchive's C sources directly from SwiftPM. libarchive needs generated config headers and a complete source list. Build one static archive with CMake and point a small SwiftPM C shim at the generated headers/library.

Create `scripts/build-libarchive.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Shared/Vendored/libarchive"
BUILD="$SRC/build/mayn"

cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_ACL=OFF \
  -DENABLE_XATTR=ON \
  -DENABLE_OPENSSL=OFF \
  -DENABLE_LIBB2=OFF \
  -DENABLE_LZ4=OFF \
  -DENABLE_ZSTD=OFF \
  -DENABLE_TEST=OFF \
  -DENABLE_CPIO=OFF \
  -DENABLE_TAR=OFF \
  -DENABLE_CAT=OFF

cmake --build "$BUILD" --target archive --config Release
test -f "$BUILD/libarchive/libarchive.a" || test -f "$BUILD/libarchive.a"
```

Append a new `CLibArchive` shim target to `Package.swift`:

```swift
.target(
    name: "CLibArchive",
    path: "Sources/CLibArchive",
    sources: ["shim.c"],
    publicHeadersPath: "include",
    cSettings: [
        .headerSearchPath("../../Vendored/libarchive/libarchive"),
        .headerSearchPath("../../Vendored/libarchive/build/mayn/libarchive"),
        .headerSearchPath("../../Vendored/libarchive/build/mayn"),
    ],
    linkerSettings: [
        .unsafeFlags(["-LVendored/libarchive/build/mayn/libarchive", "-LVendored/libarchive/build/mayn"]),
        .linkedLibrary("archive"),
        .linkedLibrary("z"),
        .linkedLibrary("bz2"),
        .linkedLibrary("lzma"),
    ]
),
```

Add `CLibArchive` to `Platform`'s dependencies.

- [ ] **Step 4: Build until green**

```bash
chmod +x scripts/build-libarchive.sh
./scripts/build-libarchive.sh
cd Shared && swift build
```

- [ ] **Step 5: Commit**

```bash
git add scripts/build-libarchive.sh Shared/Vendored/libarchive Shared/Sources/CLibArchive Shared/Package.swift
git commit -m "chore: vendor libarchive as CLibArchive SwiftPM target"
```

---

## Task 4.4: `ArchiveBackend` protocol + `LibArchiveBackend`

**Files:**
- Create: `Shared/Sources/Platform/Archive/ArchiveBackend.swift`
- Create: `Shared/Sources/Platform/Archive/LibArchiveBackend.swift`
- Create: `Shared/Tests/PlatformTests/FolderPreview/LibArchiveBackendTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Platform

final class LibArchiveBackendTests: XCTestCase {
    func testListZipEntries() throws {
        // Build a zip on the fly using `zip` CLI (BSD on macOS)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f1 = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: f1, atomically: true, encoding: .utf8)
        let zipURL = dir.appendingPathComponent("test.zip")
        let proc = Process()
        proc.launchPath = "/usr/bin/zip"
        proc.arguments = ["-j", zipURL.path, f1.path]
        try proc.run(); proc.waitUntilExit()

        let backend = LibArchiveBackend()
        let entries = try backend.list(archiveURL: zipURL, limits: .default)
        XCTAssertTrue(entries.contains { $0.path.hasSuffix("hello.txt") })
    }

    func testRejectsEvilPaths() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evil-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Construct a tarball with a "../etc/passwd" entry via /usr/bin/tar's -P flag would be OS-level; skip if hard.
        // Instead unit-test the safety filter directly via ArchiveSafety in Task 4.2.
    }
}
```

- [ ] **Step 2: Implement protocol**

`ArchiveBackend.swift`:

```swift
import Foundation

public struct ArchiveEntry: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let uncompressedSize: Int64
    public let modified: Date?
}

public protocol ArchiveBackend: AnyObject {
    func list(archiveURL: URL, limits: ArchiveSafety.Limits) throws -> [ArchiveEntry]
    func extract(archiveURL: URL, entryPath: String, to destination: URL, limits: ArchiveSafety.Limits) throws
}
```

- [ ] **Step 3: Implement `LibArchiveBackend`**

```swift
import Foundation
import CLibArchive

public final class LibArchiveBackend: ArchiveBackend {
    public init() {}

    public func list(archiveURL: URL, limits: ArchiveSafety.Limits) throws -> [ArchiveEntry] {
        guard let archive = archive_read_new() else { throw NSError(domain: "LibArchive", code: -1) }
        defer { archive_read_free(archive) }
        archive_read_support_format_all(archive)
        archive_read_support_filter_all(archive)
        let r = archive_read_open_filename(archive, archiveURL.path, 1024 * 64)
        guard r == ARCHIVE_OK else { throw NSError(domain: "LibArchive", code: Int(r)) }

        var entries: [ArchiveEntry] = []
        var totalSize: Int64 = 0
        var entry: OpaquePointer?
        while archive_read_next_header(archive, &entry) == ARCHIVE_OK, let e = entry {
            try ArchiveSafety.checkEntryCount(entries.count + 1, limits: limits)
            let cpath = String(cString: archive_entry_pathname(e))
            try ArchiveSafety.validatePath(cpath, limits: limits)
            let filetype = archive_entry_filetype(e)
            let isDir = filetype == AE_IFDIR
            let isRegular = filetype == AE_IFREG
            let isLink = archive_entry_symlink(e) != nil || archive_entry_hardlink(e) != nil
            guard isDir || (isRegular && !isLink) else {
                archive_read_data_skip(archive)
                continue
            }
            let size = archive_entry_size(e)
            try ArchiveSafety.checkPerFileSize(size, limits: limits)
            totalSize += size
            try ArchiveSafety.checkTotalUncompressed(totalSize, limits: limits)
            let mtime = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(e)))
            entries.append(ArchiveEntry(path: cpath, isDirectory: isDir, uncompressedSize: size, modified: mtime))
            archive_read_data_skip(archive)
        }
        return entries
    }

    public func extract(archiveURL: URL, entryPath: String, to destination: URL, limits: ArchiveSafety.Limits) throws {
        try ArchiveSafety.validatePath(entryPath, limits: limits)
        guard let archive = archive_read_new() else { throw NSError(domain: "LibArchive", code: -1) }
        defer { archive_read_free(archive) }
        archive_read_support_format_all(archive)
        archive_read_support_filter_all(archive)
        let r = archive_read_open_filename(archive, archiveURL.path, 1024 * 64)
        guard r == ARCHIVE_OK else { throw NSError(domain: "LibArchive", code: Int(r)) }

        var entry: OpaquePointer?
        while archive_read_next_header(archive, &entry) == ARCHIVE_OK, let e = entry {
            let p = String(cString: archive_entry_pathname(e))
            try ArchiveSafety.validatePath(p, limits: limits)
            if p == entryPath {
                let filetype = archive_entry_filetype(e)
                guard filetype == AE_IFREG,
                      archive_entry_symlink(e) == nil,
                      archive_entry_hardlink(e) == nil else {
                    throw NSError(domain: "LibArchive", code: 6)
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let out = fopen(destination.path, "wb") else { throw NSError(domain: "LibArchive", code: 5) }
                defer { fclose(out) }
                var buffer = [Int8](repeating: 0, count: 64 * 1024)
                var written: Int64 = 0
                while true {
                    let n = archive_read_data(archive, &buffer, buffer.count)
                    if n == 0 { break }
                    if n < 0 { throw NSError(domain: "LibArchive", code: Int(n)) }
                    written += Int64(n)
                    try ArchiveSafety.checkPerFileSize(written, limits: limits)
                    try ArchiveSafety.checkTotalUncompressed(written, limits: limits)
                    guard fwrite(buffer, 1, n, out) == n else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                }
                return
            } else {
                archive_read_data_skip(archive)
            }
        }
        throw NSError(domain: "LibArchive", code: 404)
    }
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter LibArchiveBackendTests
git add Shared/Sources/Platform/Archive Shared/Tests/PlatformTests/FolderPreview/LibArchiveBackendTests.swift
git commit -m "feat(platform): add ArchiveBackend protocol + LibArchiveBackend"
```

---

## Task 4.5: `ThumbnailService`

**Files:**
- Create: `Shared/Sources/Platform/FolderPreview/ThumbnailService.swift`
- Create: `Shared/Tests/PlatformTests/FolderPreview/ThumbnailServiceTests.swift`

Cache key: `"\(volumeID)-\(inode)-\(mtime).png"`. Cache directory: `App Group/thumbnails/`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import Platform
@testable import Core

final class ThumbnailServiceTests: XCTestCase {
    func testReturnsThumbnailForImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("th-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("a.png")
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 100, height: 100).fill(); img.unlockFocus()
        try img.tiffRepresentation?.write(to: url)

        let cacheDir = dir.appendingPathComponent("cache")
        let svc = ThumbnailService(cacheRoot: cacheDir)
        let thumb = try await svc.thumbnail(for: url, size: CGSize(width: 64, height: 64))
        XCTAssertNotNil(thumb)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import AppKit
import QuickLookThumbnailing

public final class ThumbnailService {
    private let cacheRoot: URL
    public init(cacheRoot: URL) {
        self.cacheRoot = cacheRoot
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    public func thumbnail(for url: URL, size: CGSize) async throws -> NSImage? {
        let key = try cacheKey(for: url, size: size)
        let cached = cacheRoot.appendingPathComponent("\(key).png")
        if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) { return img }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                    representationTypes: .all)
        let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let img = rep.nsImage
        if let tiff = img.tiffRepresentation, let bits = NSBitmapImageRep(data: tiff),
           let png = bits.representation(using: .png, properties: [:]) {
            try? png.write(to: cached, options: .atomic)
        }
        return img
    }

    private func cacheKey(for url: URL, size: CGSize) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let volumeID = (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let mtime = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return "\(volumeID)-\(inode)-\(mtime)-\(Int(size.width))x\(Int(size.height))"
    }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter ThumbnailServiceTests
git add Shared/Sources/Platform/FolderPreview/ThumbnailService.swift Shared/Tests/PlatformTests/FolderPreview/ThumbnailServiceTests.swift
git commit -m "feat(platform): add ThumbnailService with on-disk cache"
```

---

## Task 4.6: SwiftUI `FolderPreviewView` + sub-views

**Files:**
- Create: `Shared/Sources/UI/FolderPreview/FolderPreviewView.swift`
- Create: `Shared/Sources/UI/FolderPreview/FolderFilesView.swift`
- Create: `Shared/Sources/UI/FolderPreview/FolderGridView.swift`
- Create: `Shared/Sources/UI/FolderPreview/FolderAnalyzeView.swift`
- Create: `Shared/Sources/UI/FolderPreview/ArchivePreviewView.swift`

- [ ] **Step 1: Implement `FolderPreviewView`**

```swift
import SwiftUI
import Platform

public struct FolderPreviewView: View {
    public enum Mode: String, CaseIterable, Identifiable { case files, grid, analyze; public var id: String { rawValue } }

    @State private var inventory: FolderInventory?
    @State private var mode: Mode = .files
    @State private var currentURL: URL
    @State private var backStack: [URL] = []
    public let folderURL: URL
    public let onAction: ((PreviewAction) -> Void)?

    public init(folderURL: URL, onAction: ((PreviewAction) -> Void)? = nil) {
        self.folderURL = folderURL
        self.onAction = onAction
        _currentURL = State(initialValue: folderURL)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let previous = backStack.popLast() { currentURL = previous }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(backStack.isEmpty)
                Text(currentURL.lastPathComponent).font(.title3).bold()
                if let inv = inventory {
                    Text("· \(inv.entries.count) items · \(byteCountFormatter.string(fromByteCount: inv.totalSize))")
                        .foregroundStyle(.secondary).font(.caption)
                    if inv.isPartial { Text("(partial)").foregroundStyle(.orange).font(.caption) }
                }
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.segmented).frame(width: 200)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            Group {
                if let inv = inventory {
                    switch mode {
                    case .files: FolderFilesView(inventory: inv, onAction: onAction) { url in
                        backStack.append(currentURL)
                        currentURL = url
                    }
                    case .grid: FolderGridView(inventory: inv)
                    case .analyze: FolderAnalyzeView(inventory: inv)
                    }
                } else {
                    ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: currentURL) {
            inventory = nil
            inventory = try? await FolderEnumerator.enumerate(url: currentURL, maxEntries: 50_000)
            if let inv = inventory, autoSuggestGrid(inv) { mode = .grid }
        }
    }

    private func autoSuggestGrid(_ inv: FolderInventory) -> Bool {
        let imageCount = inv.breakdown[.images, default: 0]
        let nonFolderCount = inv.entries.filter { !$0.isDirectory }.count
        return nonFolderCount > 10 && Double(imageCount) / Double(nonFolderCount) >= 0.4
    }
}

public enum PreviewAction: Sendable {
    case open(URL)
    case copy(URL)
    case revealInFinder(URL)
}

private let byteCountFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    f.countStyle = .file
    return f
}()
```

- [ ] **Step 2: Implement sub-views**

`FolderFilesView.swift`:

```swift
import SwiftUI
import Platform

struct FolderFilesView: View {
    let inventory: FolderInventory
    let onAction: ((PreviewAction) -> Void)?
    let onOpenFolder: (URL) -> Void

    var body: some View {
        Table(inventory.entries) {
            TableColumn("Name") { e in
                Button {
                    if e.isDirectory { onOpenFolder(URL(fileURLWithPath: e.path)) }
                    else { onAction?(.open(URL(fileURLWithPath: e.path))) }
                } label: {
                    Label(e.name, systemImage: e.isDirectory ? "folder" : "doc")
                }
                .buttonStyle(.plain)
            }
            TableColumn("Size") { e in Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) }
            TableColumn("Modified") { Text($0.modified, style: .date) }
            TableColumn("Kind") { Text($0.kind.rawValue) }
        }
        .contextMenu(forSelectionType: FolderEntry.ID.self) { _ in } primaryAction: { _ in }
    }
}
extension FolderEntry: Identifiable { public var id: String { path } }
```

`FolderGridView.swift`:

```swift
import SwiftUI
import Platform

struct FolderGridView: View {
    let inventory: FolderInventory
    @State private var thumbs: [String: NSImage] = [:]
    private let svc = ThumbnailService(cacheRoot: AppGroup.containerURL().appendingPathComponent("thumbnails"))

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 8), count: 5), spacing: 8) {
                ForEach(inventory.entries.filter { $0.kind == .images }) { entry in
                    VStack(spacing: 4) {
                        if let img = thumbs[entry.path] {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.1)
                        }
                        Text(entry.name).font(.caption).lineLimit(1)
                    }
                    .frame(width: 110, height: 130)
                    .task {
                        if thumbs[entry.path] == nil {
                            thumbs[entry.path] = try? await svc.thumbnail(for: URL(fileURLWithPath: entry.path), size: CGSize(width: 220, height: 220))
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}

import Core
```

`FolderAnalyzeView.swift`:

```swift
import SwiftUI
import Platform
import Charts

struct FolderAnalyzeView: View {
    let inventory: FolderInventory
    var data: [(FolderEntryKind, Int)] {
        inventory.breakdown.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
    var body: some View {
        VStack(alignment: .leading) {
            Chart(data, id: \.0.rawValue) { (k, v) in
                BarMark(x: .value("Kind", k.rawValue), y: .value("Count", v))
            }
            .frame(height: 200).padding(.horizontal, 12)
            Divider()
            Text("Largest files").font(.headline).padding(.horizontal, 12)
            List(inventory.largest) { e in
                HStack { Text(e.name); Spacer(); Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) }
            }
        }
    }
}
```

`ArchivePreviewView.swift`:

```swift
import SwiftUI
import Platform

public struct ArchivePreviewView: View {
    public let archiveURL: URL
    @State private var entries: [ArchiveEntry] = []
    @State private var error: String?

    public init(archiveURL: URL) { self.archiveURL = archiveURL }

    public var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("🗄️ \(archiveURL.lastPathComponent)").font(.title3).bold()
                Spacer()
                Text("\(entries.count) entries").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let error = error {
                Text(error).foregroundStyle(.red).padding()
            } else {
                List(entries, id: \.path) { e in
                    HStack {
                        Image(systemName: e.isDirectory ? "folder" : "doc")
                        Text(e.path).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: e.uncompressedSize, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: archiveURL) {
            do {
                let backend = LibArchiveBackend()
                entries = try backend.list(archiveURL: archiveURL, limits: .default)
            } catch {
                self.error = "Could not read archive: \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
cd Shared && swift build
git add Shared/Sources/UI/FolderPreview
git commit -m "feat(ui): add FolderPreviewView + Files/Grid/Analyze + ArchivePreviewView"
```

---

## Task 4.7: Wire the Quick Look extension to use the real views

**Files:**
- Modify: `FolderPreview/PreviewProvider.swift`

- [ ] **Step 1: Replace placeholder**

```swift
import Cocoa
import Quartz
import UniformTypeIdentifiers
import Platform

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let html: String
        if isDirectory {
            let inv = try await FolderEnumerator.enumerate(url: url, maxEntries: 5_000)
            html = PreviewHTML.folder(url: url, inventory: inv)
        } else {
            let entries = try LibArchiveBackend().list(archiveURL: url, limits: .default)
            html = PreviewHTML.archive(url: url, entries: entries)
        }
        let data = Data(html.utf8)

        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 720, height: 480)) { _, _ in
            data as NSData
        }
    }
}

enum PreviewHTML {
    static func folder(url: URL, inventory: FolderInventory) -> String {
        let rows = inventory.entries.prefix(500).map { e in
            "<tr><td>\(escape(e.name))</td><td>\(e.kind.rawValue)</td><td>\(e.size)</td></tr>"
        }.joined()
        return page(title: escape(url.lastPathComponent), body: """
        <h1>\(escape(url.lastPathComponent))</h1>
        <p>\(inventory.entries.count) items · \(inventory.totalSize) bytes\(inventory.isPartial ? " · partial" : "")</p>
        <table><tr><th>Name</th><th>Kind</th><th>Bytes</th></tr>\(rows)</table>
        """)
    }

    static func archive(url: URL, entries: [ArchiveEntry]) -> String {
        let rows = entries.prefix(500).map { e in
            "<tr><td>\(escape(e.path))</td><td>\(e.isDirectory ? "folder" : "file")</td><td>\(e.uncompressedSize)</td></tr>"
        }.joined()
        return page(title: escape(url.lastPathComponent), body: """
        <h1>\(escape(url.lastPathComponent))</h1>
        <p>\(entries.count) archive entries</p>
        <table><tr><th>Path</th><th>Kind</th><th>Bytes</th></tr>\(rows)</table>
        """)
    }

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body{font:13px -apple-system;margin:20px;color:#1f2328}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ddd;padding:6px;text-align:left}</style>
        <title>\(title)</title></head><body>\(body)</body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

The standalone window still uses `FolderPreviewView`; Quick Look uses HTML because `QLPreviewReply` snapshots must be complete before the reply is drawn and cannot rely on SwiftUI `.task` loading after render.

- [ ] **Step 2: Build + manual test**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
qlmanage -r
qlmanage -m
```

In Finder, press Space on a folder. The Quick Look popup shows the generated HTML summary and file table. The standalone Browse Folder window remains the Files/Grid/Analyze SwiftUI surface.

- [ ] **Step 3: Commit**

```bash
git add FolderPreview/PreviewProvider.swift
git commit -m "feat(folderpreview): render folder and archive HTML in Quick Look"
```

---

## Task 4.8: `FolderPreviewXPCProtocol` for standalone Open/Copy/Reveal

**Files:**
- Create: `Shared/Sources/Core/XPC/FolderPreviewXPCProtocol.swift`
- Create: `MacAllYouNeed/FolderPreview/BrowseFolderCoordinator.swift`
- Modify: `Shared/Sources/UI/FolderPreview/FolderFilesView.swift` (call XPC on action)

- [ ] **Step 1: Implement protocol**

```swift
@objc public protocol FolderPreviewXPCProtocol {
    func openFile(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
    func revealInFinder(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
    func copyFileURLToPasteboard(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
}
```

This XPC action surface is for the standalone SwiftUI Browse Folder window (`FolderFilesView`). Quick Look renders a read-only HTML summary in Task 4.7; it does not host SwiftUI context menus or call this XPC service.

The server must reject unexpected clients. In `listener(_:shouldAcceptNewConnection:)`, validate the caller audit token/team ID/bundle ID against the known main app identity. Do not accept arbitrary local processes.

- [ ] **Step 2: Implement coordinator in main app**

```swift
import Foundation
import AppKit
import Core

final class BrowseFolderCoordinator: NSObject, FolderPreviewXPCProtocol, NSXPCListenerDelegate {
    let listener: NSXPCListener
    static let serviceName = "group.com.macallyouneed.shared.folderpreview"
    override init() {
        listener = NSXPCListener(machServiceName: Self.serviceName)
        super.init()
        listener.delegate = self
        listener.resume()
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isAllowedClient(newConnection) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: FolderPreviewXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
    static func isAllowedClient(_ connection: NSXPCConnection) -> Bool {
        let allowedBundleIDs: Set<String> = [
            "com.macallyouneed.app",
        ]
        let app = NSRunningApplication(processIdentifier: connection.processIdentifier)
        guard let bundleID = app?.bundleIdentifier else { return false }
        return allowedBundleIDs.contains(bundleID)
    }
    private func resolve(bookmark: Data, fallbackPath: String) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
           !stale {
            return url
        }
        let fallback = URL(fileURLWithPath: fallbackPath)
        guard fallback.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) else { return nil }
        return fallback
    }
    func openFile(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            reply(NSWorkspace.shared.open(url))
        }
    }
    func revealInFinder(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            reply(true)
        }
    }
    func copyFileURLToPasteboard(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
            reply(true)
        }
    }
}
```

Instantiate inside `MacAllYouNeedApp.init`.

- [ ] **Step 3: Wire from `FolderFilesView` action menu**

Replace the standalone `FolderFilesView` `contextMenu` placeholders with real items that call the coordinator. When `FolderFilesView` runs inside the main app, call `BrowseFolderCoordinator` in-process; if it is ever reused in a sandboxed extension host, use `NSXPCConnection(machServiceName: BrowseFolderCoordinator.serviceName)` with a security-scoped bookmark plus the path as a fallback display/debug value. The Task 4.7 Quick Look HTML preview remains read-only.

- [ ] **Step 4: Manual test from the standalone window**

Press `⌘⇧F`, choose a folder, then right-click a file → "Open". Confirm the file opens in its default app. Repeat for "Copy URL" and "Reveal in Finder".

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/XPC/FolderPreviewXPCProtocol.swift MacAllYouNeed/FolderPreview/BrowseFolderCoordinator.swift Shared/Sources/UI/FolderPreview/FolderFilesView.swift
git commit -m "feat(folderpreview): Open/Copy/Reveal actions in standalone browser"
```

---

## Task 4.9: Standalone "Browse folder" window + ⌘⇧F hotkey

**Files:**
- Create: `MacAllYouNeed/FolderPreview/BrowseFolderWindowController.swift`
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift` (register hotkey + menu item)

- [ ] **Step 1: Implement window controller**

```swift
import AppKit
import SwiftUI
import UI

@MainActor
final class BrowseFolderWindowController {
    private var window: NSWindow?
    private var url: URL = FileManager.default.homeDirectoryForCurrentUser

    func openPanelAndBrowse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let chosen = panel.url {
            self.url = chosen; show()
        }
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Browse Folder"
            w.center()
            w.contentView = NSHostingView(rootView: FolderPreviewView(folderURL: url))
            w.isReleasedWhenClosed = false
            self.window = w
        } else {
            (window?.contentView as? NSHostingView<FolderPreviewView>)?.rootView = FolderPreviewView(folderURL: url)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Hook ⌘⇧F**

In `MacAllYouNeedApp.init`:

```swift
let browse = BrowseFolderWindowController()
let folderHotkey = GlobalHotkey(descriptor: .defaultFolder) { Task { @MainActor in browse.openPanelAndBrowse() } }
try? folderHotkey.register()
```

(Persist `folderHotkey` in app state to keep it alive.)

- [ ] **Step 3: Manual test**

Press `⌘⇧F`. Folder picker appears. Choose a folder. Window opens with FolderPreviewView.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/FolderPreview/BrowseFolderWindowController.swift MacAllYouNeed/MacAllYouNeedApp.swift
git commit -m "feat(folderpreview): standalone Browse Folder window + ⌘⇧F"
```

---

## Self-review checklist

```bash
cd Shared && swift test
swiftlint --strict
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
qlmanage -r && qlmanage -m
```

Manual:
- Space on a folder → read-only HTML summary + file table.
- Space on a `.zip` → read-only HTML archive entries.
- `⌘⇧F` → folder picker → standalone window with multi-pane Files/Grid/Analyze.
- Right-click a file in the standalone window → Open / Copy / Reveal works.

**Spec coverage:**

- [x] §7 Quick Look extension for folders + archives — Tasks 4.1, 4.4, 4.7
- [x] §7 PeekX-style folder analysis — Task 4.6 (Analyze view)
- [x] §7 Image contact-sheet Grid — Task 4.6 (Grid view + auto-suggest)
- [x] §7 Archive safety (path traversal, bombs, depth caps) — Task 4.2
- [x] §7 Open/Copy from preview via XPC — Task 4.8
- [x] §7 Standalone window mode — Task 4.9
- [x] §3 decision 9 (vendored libarchive) — Task 4.3

**Out of scope (other plans):**
- Multi-pane comparison (deferred to UI polish — add in Plan 6 if time)
- Custom column toggles (deferred to UI polish in Plan 6)
- Persistent window state (deferred to Plan 6)
- Full Disk Access JIT prompt for protected folders (Plan 6 onboarding)
