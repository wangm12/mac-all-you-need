# FolderPreview XPC Spike — Findings

**Status: FALLBACK ADOPTED**

## Findings

Sandboxed Quick Look extensions (`com.apple.security.app-sandbox: true`) cannot reach
arbitrary Mach services without additional entitlements
(`com.apple.security.temporary-exception.mach-lookup.global-name`), which are not
available to Personal Team / free-account-signed builds and are rejected by notarization
unless explicitly justified.

Additionally, `QLPreviewProvider` + `QLPreviewReply(dataOfContentType:)` hangs
indefinitely on macOS 26.4 (Xcode 26). The working API is `NSViewController +
QLPreviewingController.preparePreviewOfFile(at:completionHandler:)`.

## Decision

Quick Look extension: **read-only HTML preview** rendered in a `WKWebView` embedded
in `PreviewViewController`. No XPC from the extension.

Standalone app: **in-process** `BrowseFolderCoordinator` handles Open/Copy/Reveal
actions. The `FolderPreviewXPCProtocol` is defined for future use if the extension
ever gains the required entitlement.

## Service name reserved

`group.com.macallyouneed.shared.folderpreview` — defined but not yet used by the extension.
