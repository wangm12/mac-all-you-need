# Pasteboard Capture

This module turns `NSPasteboard.general` changes into clipboard history items.

## Image Representation Collapse

macOS screenshot and image tools often publish the same copied image as several
pasteboard representations in one change, commonly:

- `public.png`
- `public.tiff`
- `public.file-url`

`SystemPasteboardReader.currentItems()` exposes those as separate
`PasteboardItem` values so callers can still inspect the raw pasteboard shape.
The history writer must not persist every representation, because one screenshot
would become multiple rows in the clipboard UI.

`PasteboardChange.historyCaptureItems` is the boundary used by the daemon before
writing history:

- If a PNG representation exists, persist only that PNG.
- Otherwise, if a TIFF representation exists, persist only that TIFF.
- If no image representation exists, keep the original item list.

This preserves normal text/file behavior while making screenshot copies appear
as one image row.

## Change Count Baseline

Some image pasteboard reads can advance `NSPasteboard.changeCount` while data is
being materialized. `PasteboardObserver` handles two cases:

- If item reading returns content, it baselines to the post-read change count so
  the same image is not captured again.
- If item reading returns no content, it keeps the pre-read baseline so the
  bumped change count is retried on the next poll.

That second case prevents promised image data from disappearing when it becomes
available one tick later.

## Code

- `Shared/Sources/Platform/Pasteboard/PasteboardChange.swift`
- `Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift`
- `ClipboardDaemon/ClipboardDaemonMain.swift`

## Tests

The behavior is covered by:

- `Shared/Tests/PlatformTests/PasteboardChangeTests.swift`
- `Shared/Tests/PlatformTests/PasteboardObserverTests.swift`

Run:

```sh
cd Shared
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PasteboardChangeTests
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PasteboardObserverTests
```
