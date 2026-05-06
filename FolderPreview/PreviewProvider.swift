import Cocoa
import Core
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    private let label = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32)
        ])
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let kind = isDirectory ? "Folder" : "Archive"
        let fallback = AppGroup.isUsingFallbackContainer() ? " (FALLBACK)" : ""
        label.stringValue = "\(kind) preview: \(url.lastPathComponent)\nContainer: \(AppGroup.containerURL().path)\(fallback)"
        handler(nil)
    }
}
