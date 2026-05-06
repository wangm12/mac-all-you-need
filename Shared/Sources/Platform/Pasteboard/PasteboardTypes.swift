import AppKit
import UniformTypeIdentifiers

public enum PasteboardUTI {
    public static let plainText = NSPasteboard.PasteboardType("public.utf8-plain-text")
    public static let rtf = NSPasteboard.PasteboardType("public.rtf")
    public static let html = NSPasteboard.PasteboardType("public.html")
    public static let png = NSPasteboard.PasteboardType("public.png")
    public static let tiff = NSPasteboard.PasteboardType("public.tiff")
    public static let fileURL = NSPasteboard.PasteboardType("public.file-url")
    public static let finderNode = NSPasteboard.PasteboardType("com.apple.finder.node")
    public static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
}
