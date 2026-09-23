import AppKit
import UniformTypeIdentifiers
@main
struct BrowserDragTypesHarness {
    static func main() {
        for type in [UTType.png, .jpeg, .tiff, .gif, .heic, .webP] {
            precondition(NotchDragContent.accepts([NSPasteboard.PasteboardType(type.identifier)]))
        }
        for type: NSPasteboard.PasteboardType in [.fileURL, .URL, .string] {
            precondition(NotchDragContent.accepts([type]))
        }
        precondition(!NotchDragContent.accepts([]))
        precondition(!NotchDragContent.accepts([NSPasteboard.PasteboardType("org.example.unsupported")]))
        print("BrowserDragTypesHarness: PASS")
    }
}
