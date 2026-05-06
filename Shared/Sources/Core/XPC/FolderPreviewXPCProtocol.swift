import Foundation

@objc public protocol FolderPreviewXPCProtocol {
    func openFile(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
    func revealInFinder(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
    func copyFileURLToPasteboard(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void)
}
