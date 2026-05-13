# Folder Preview

Quick Look preview extension for inspecting folders and common archive files inside Finder.

## What It Does

Folder Preview replaces the default Finder preview for supported folders and archives with a native AppKit interface:

- Immediate top-level folder listing.
- Expandable child folders with lazy loading.
- Segmented filters for `All`, `Folders`, `Images`, `Docs`, and `Media`.
- Row selection with an optional right-side detail preview.
- Image thumbnails generated with ImageIO; PDF/video thumbnails use Quick Look thumbnail fallback.
- Archive listing for supported archive formats without extracting contents for preview.

Supported Quick Look content types are declared in [Info.plist](Info.plist):

- `public.folder`
- `public.zip-archive`
- `org.7-zip.7-zip-archive`
- `com.rarlab.rar-archive`
- `public.tar-archive`
- `org.gnu.gnu-zip-archive`
- `public.bzip2-archive`

## User Experience

The preview opens quickly by returning from `preparePreviewOfFile` immediately, then loading folder or archive contents asynchronously.

For folders:

- Only direct children are shown at first.
- Folders appear before files.
- Names use natural sorting.
- Child folders expand on demand.
- The side preview pane is hidden until a row is selected.
- Selecting an image row shows a downsampled thumbnail and metadata.

For archives:

- Entries are listed in a flat table.
- Archive rows show metadata only.
- Archive members are not extracted for side preview.

## Performance Rules

This extension runs inside Quick Look, so selection and scrolling must stay lightweight.

- Do not enumerate a full folder tree on initial preview.
- Do not enumerate child folders on selection.
- Do not decode full-size images on the main thread.
- Do not extract archive members just because a row is selected.
- Keep thumbnail work cancelable and guarded against stale selections.
- Prefer bounded thumbnails over full previews inside the side pane.

The current selection preview path:

1. Update metadata synchronously.
2. Show the fallback file icon immediately.
3. Wait briefly to avoid doing thumbnail work while the user is moving through rows.
4. Generate a thumbnail off the main actor.
5. Apply the result only if the same row is still selected.

## Key Files

- [PreviewProvider.swift](PreviewProvider.swift): Quick Look controller, native table/outline UI, filters, row selection, and side preview pane.
- [FolderEnumerator.swift](../Shared/Sources/Platform/FolderPreview/FolderEnumerator.swift): folder enumeration and file-kind classification.
- [FolderPreviewDisplay.swift](../Shared/Sources/Platform/FolderPreview/FolderPreviewDisplay.swift): sorting, filter matching, display labels, and thumbnail eligibility.
- [LibArchiveBackend.swift](../Shared/Sources/Platform/Archive/LibArchiveBackend.swift): archive entry listing.
- [FolderPreviewDisplayTests.swift](../Shared/Tests/PlatformTests/FolderPreview/FolderPreviewDisplayTests.swift): display/filter behavior tests.
- [FolderEnumeratorTests.swift](../Shared/Tests/PlatformTests/FolderPreview/FolderEnumeratorTests.swift): enumeration behavior tests.

## Build And Reload

Build the app and embedded extension:

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
```

After changing the extension, reset Quick Look and relaunch the debug app:

```bash
APP="/Users/mingjie.wang/Library/Developer/Xcode/DerivedData/MacAllYouNeed-cisxkqtqalejdbbeflfoyrmwwgyt/Build/Products/Debug/MacAllYouNeed.app"
EXT="$APP/Contents/PlugIns/FolderPreview.appex"

pkill -x MacAllYouNeed 2>/dev/null || true
pkill -x ClipboardDaemon 2>/dev/null || true
pluginkit -a "$EXT" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R "$APP"
qlmanage -r
qlmanage -r cache
killall -KILL QuickLookUIService 2>/dev/null || true
killall -KILL QuickLookSatellite 2>/dev/null || true
killall -KILL quicklookd 2>/dev/null || true
open -n "$APP"
```

Confirm registration:

```bash
pluginkit -m -v -p com.apple.quicklook.preview | rg "MacAllYouNeed|FolderPreview"
```

## Verification Checklist

Before handing off a folder preview change:

- Run `git diff --check -- FolderPreview/PreviewProvider.swift`.
- Run the Xcode build command above.
- If shared folder/archive code changed, run:

```bash
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```

Manual Finder checks:

- Preview a folder with no selected row; the side pane should be hidden.
- Select an image; the side pane should show the actual image thumbnail.
- Select a folder; the side pane should show metadata without loading children.
- Expand a child folder; loading should be lazy and cancellable.
- Switch filters; selection should clear and the side pane should hide.
- Preview a large archive; it should list entries without extracting them.

## Known Limits

- Archive entry side previews are metadata-only.
- The initial folder view is limited to direct children.
- Child folder expansion is capped for responsiveness.
- Markdown, source-code rendering, and video playback are intentionally not implemented in the side pane yet.
