import Foundation

@objc public class ClipboardXPCMeta: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let id: String
    @objc public let modified: Date
    @objc public let kind: String
    @objc public let preview: String
    @objc public let sourceAppBundleID: String?
    @objc public let imageWidth: Int
    @objc public let imageHeight: Int
    @objc public let imageBlobID: String?
    @objc public let customLabel: String?

    public init(
        id: String,
        modified: Date,
        kind: String,
        preview: String,
        sourceAppBundleID: String? = nil,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        imageBlobID: String? = nil,
        customLabel: String? = nil
    ) {
        self.id = id
        self.modified = modified
        self.kind = kind
        self.preview = preview
        self.sourceAppBundleID = sourceAppBundleID
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageBlobID = imageBlobID
        self.customLabel = customLabel
    }

    public required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let kind = coder.decodeObject(of: NSString.self, forKey: "kind") as String?,
              let preview = coder.decodeObject(of: NSString.self, forKey: "preview") as String?,
              let modified = coder.decodeObject(of: NSDate.self, forKey: "modified") as Date?
        else { return nil }
        self.id = id
        self.modified = modified
        self.kind = kind
        self.preview = preview
        sourceAppBundleID = coder.decodeObject(of: NSString.self, forKey: "sourceAppBundleID") as String?
        imageWidth = coder.decodeInteger(forKey: "imageWidth")
        imageHeight = coder.decodeInteger(forKey: "imageHeight")
        imageBlobID = coder.decodeObject(of: NSString.self, forKey: "imageBlobID") as String?
        customLabel = coder.decodeObject(of: NSString.self, forKey: "customLabel") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(modified as NSDate, forKey: "modified")
        coder.encode(kind as NSString, forKey: "kind")
        coder.encode(preview as NSString, forKey: "preview")
        if let sourceAppBundleID {
            coder.encode(sourceAppBundleID as NSString, forKey: "sourceAppBundleID")
        }
        coder.encode(imageWidth, forKey: "imageWidth")
        coder.encode(imageHeight, forKey: "imageHeight")
        if let imageBlobID {
            coder.encode(imageBlobID as NSString, forKey: "imageBlobID")
        }
        if let customLabel {
            coder.encode(customLabel as NSString, forKey: "customLabel")
        }
    }
}

@objc public class ClipboardXPCList: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool {
        true
    }

    @objc public let items: [ClipboardXPCMeta]
    @objc public let nextPageToken: String?

    public init(items: [ClipboardXPCMeta], nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }

    public required init?(coder: NSCoder) {
        let cls: [AnyClass] = [NSArray.self, ClipboardXPCMeta.self]
        guard let items = coder.decodeObject(of: cls, forKey: "items") as? [ClipboardXPCMeta] else { return nil }
        self.items = items
        nextPageToken = coder.decodeObject(of: NSString.self, forKey: "next") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(items as NSArray, forKey: "items")
        if let next = nextPageToken { coder.encode(next as NSString, forKey: "next") }
    }
}

@objc public class ClipboardXPCBlobRef: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool {
        true
    }

    @objc public let blobID: String
    @objc public let encryptedFilePath: String
    @objc public let kind: String

    public init(blobID: String, encryptedFilePath: String, kind: String) {
        self.blobID = blobID
        self.encryptedFilePath = encryptedFilePath
        self.kind = kind
    }

    public required init?(coder: NSCoder) {
        guard let blobID = coder.decodeObject(of: NSString.self, forKey: "blobID") as String?,
              let path = coder.decodeObject(of: NSString.self, forKey: "encryptedFilePath") as String?,
              let kind = coder.decodeObject(of: NSString.self, forKey: "kind") as String?
        else { return nil }
        self.blobID = blobID
        encryptedFilePath = path
        self.kind = kind
    }

    public func encode(with coder: NSCoder) {
        coder.encode(blobID as NSString, forKey: "blobID")
        coder.encode(encryptedFilePath as NSString, forKey: "encryptedFilePath")
        coder.encode(kind as NSString, forKey: "kind")
    }
}

@objc public protocol ClipboardXPCProtocol {
    func listItems(query: String?, pageToken: String?, limit: Int, reply: @escaping (ClipboardXPCList) -> Void)
    func metasByIDs(ids: [String], reply: @escaping (ClipboardXPCList) -> Void)
    func bodyText(forID id: String, reply: @escaping (String?) -> Void)
    func bodyFileURLs(forID id: String, reply: @escaping ([String]?) -> Void)
    func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void)
    func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void)
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool, reply: @escaping (String) -> Void)
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool, reply: @escaping (String) -> Void)
    func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool, reply: @escaping (String?) -> Void)
    func deleteItem(id: String, reply: @escaping (Bool) -> Void)
    func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void)
    func registerCallback(reply: @escaping (Bool) -> Void)
    func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void)
    /// Asks the daemon to evict every clipboard record older than the given
    /// number of days, plus the matching FTS rows and image blobs. Routed
    /// through XPC so the daemon — which holds the writer lock on the SQLite
    /// files — owns the deletion, avoiding cross-process write races.
    func runRetention(maxAgeDays: Int, reply: @escaping (Bool) -> Void)
}

@objc public class SnippetXPCDTO: NSObject, NSSecureCoding, Identifiable {
    public static var supportsSecureCoding: Bool { true }
    @objc public let id: String
    @objc public let name: String
    @objc public let trigger: String?

    public init(id: String, name: String, trigger: String?) {
        self.id = id; self.name = name; self.trigger = trigger
    }

    public required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?
        else { return nil }
        self.id = id; self.name = name
        self.trigger = coder.decodeObject(of: NSString.self, forKey: "trigger") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(name as NSString, forKey: "name")
        if let trigger { coder.encode(trigger as NSString, forKey: "trigger") }
    }
}

@objc public protocol ClipboardXPCClientCallback {
    func itemsInvalidated()
}
