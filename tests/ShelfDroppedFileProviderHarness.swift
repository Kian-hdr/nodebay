import AppKit
import Foundation

@main
struct ShelfDroppedFileProviderHarness {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nodebay-drop-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Dropped File.txt")
        try Data("persistent shelf fixture".utf8).write(to: source, options: .atomic)
        guard let provider = NSItemProvider(contentsOf: source) else {
            throw HarnessError.providerCreation
        }
        guard let reference = await provider.extractDroppedFileReference() else {
            throw HarnessError.referenceExtraction
        }
        guard reference.url.standardizedFileURL == source.standardizedFileURL else {
            throw HarnessError.wrongURL
        }
        guard await Bookmark(data: reference.bookmarkData).validate() else {
            throw HarnessError.invalidBookmark
        }
        print("ShelfDroppedFileProviderHarness: PASS")
    }

    enum HarnessError: Error {
        case providerCreation
        case referenceExtraction
        case wrongURL
        case invalidBookmark
    }
}
