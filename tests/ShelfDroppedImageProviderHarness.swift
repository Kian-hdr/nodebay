import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Sendable {
    enum Kind: Sendable { case file(bookmark: Data), link(url: URL), text(string: String) }
    let kind: Kind
    let isTemporary: Bool
}
enum MediaDownloaderService {
    static func validatedURL(from text: String) throws -> URL {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme) else { throw Failure.invalid }
        return url
    }
}
enum Failure: Error { case invalid }

@main
struct ShelfDroppedImageProviderHarness {
    static func main() async throws {
        if CommandLine.arguments.contains("--current-drag") {
            let pasteboard = NSPasteboard(name: .drag)
            guard let data = pasteboard.data(forType: .init(UTType.jpeg.identifier)),
                  NSItemProvider.validatedImageExtension(for: data) == "jpeg" else { throw Failure.invalid }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
                completion(data, nil); return nil
            }
            if let url = pasteboard.data(forType: .URL) {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
                    completion(url, nil); return nil
                }
            }
            let items = await ShelfDropService.items(from: [provider])
            guard items.count == 1, case .file(let bookmark) = items[0].kind,
                  let output = Bookmark(data: bookmark).resolvedURL,
                  try Data(contentsOf: output) == data else { throw Failure.invalid }
            NodebayManagedFileStorage.removeFailedOutput(at: output, category: .media)
            print("Current Chrome drag JPEG persisted byte-for-byte: PASS (\(data.count) bytes)")
            return
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for format in [NSBitmapImageRep.FileType.png, .tiff, .jpeg] {
            let data = bitmap.representation(using: format, properties: [:])!
            let type: UTType = format == .png ? .png : format == .tiff ? .tiff : .jpeg
            let provider = NSItemProvider()
            provider.suggestedName = "../../image.webloc"
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                completion(data, nil); return nil
            }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
                completion(Data("https://example.com/enclosing-page".utf8), nil); return nil
            }
            let items = await ShelfDropService.items(from: [provider])
            guard items.count == 1, !items[0].isTemporary,
                  case .file(let bookmark) = items[0].kind,
                  let output = Bookmark(data: bookmark).resolvedURL,
                  output.path.contains("Nodebay/Generated/Media/"),
                  output.pathExtension != "webloc",
                  try Data(contentsOf: output) == data else { throw Failure.invalid }
            NodebayManagedFileStorage.removeFailedOutput(at: output, category: .media)
        }
        let link = NSItemProvider(item: URL(string: "https://example.com/link")! as NSURL,
                                  typeIdentifier: UTType.url.identifier)
        let links = await ShelfDropService.items(from: [link])
        guard links.count == 1, case .link(let url) = links[0].kind,
              url.absoluteString == "https://example.com/link" else { throw Failure.invalid }
        let textProvider = NSItemProvider(item: "plain note" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
        let notes = await ShelfDropService.items(from: [textProvider])
        guard notes.count == 1, case .text(let text) = notes[0].kind, text == "plain note" else { throw Failure.invalid }

        guard NSItemProvider.validatedImageExtension(for: Data("not an image".utf8)) == nil,
              NSItemProvider.validatedImageExtension(for: Data(repeating: 0, count: 32 * 1_024 * 1_024 + 1)) == nil
        else { throw Failure.invalid }
        let corruptImage = NSItemProvider(item: Data("invalid image".utf8) as NSData, typeIdentifier: UTType.png.identifier)
        guard await ShelfDropService.items(from: [corruptImage]).isEmpty else { throw Failure.invalid }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = Data("provider owned".utf8)
        try bytes.write(to: source)
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.data.identifier)
        guard await provider.loadData() == bytes, try Data(contentsOf: source) == bytes else { throw Failure.invalid }
        let stalled = NSItemProvider()
        stalled.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 10.2) { completion(Data(), nil) }
            return Progress(totalUnitCount: 1)
        }
        let started = Date()
        guard await ShelfDropService.items(from: [stalled]).isEmpty,
              Date().timeIntervalSince(started) < 12 else { throw Failure.invalid }
        try await Task.sleep(for: .milliseconds(400)) // Late callback must not resume twice.
        print("ShelfDroppedImageProviderHarness: PASS")
    }
}
