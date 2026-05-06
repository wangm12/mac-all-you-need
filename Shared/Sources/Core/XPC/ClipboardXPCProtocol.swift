import Foundation

@objc public class ClipboardXPCMeta: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool {
        true
    }

    @objc public let id: String
    @objc public let modified: Date
    @objc public let kind: String
    @objc public let preview: String

    public init(id: String, modified: Date, kind: String, preview: String) {
        self.id = id
        self.modified = modified
        self.kind = kind
        self.preview = preview
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
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(modified as NSDate, forKey: "modified")
        coder.encode(kind as NSString, forKey: "kind")
        coder.encode(preview as NSString, forKey: "preview")
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
    func bodyText(forID id: String, reply: @escaping (String?) -> Void)
    func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void)
    func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void)
    func registerCallback(reply: @escaping (Bool) -> Void)
}

@objc public protocol ClipboardXPCClientCallback {
    func itemsInvalidated()
}
