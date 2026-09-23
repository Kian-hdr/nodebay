//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        // Process providers concurrently for better performance with large drops
        await withTaskGroup(of: [ShelfItem].self) { group in
            for provider in providers {
                group.addTask {
                    await processProvider(provider)
                }
            }
            
            var results: [ShelfItem] = []
            results.reserveCapacity(providers.count)
            
            for await items in group {
                results.append(contentsOf: items)
            }
            
            return results
        }
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> [ShelfItem] {
        // Finder file references remain references. Browser images, however, must
        // win over accompanying webpage URLs and become durable local copies.
        if !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let image = await provider.extractDroppedImage() {
            let suggested = provider.suggestedName ?? "Dropped Image"
            let stem = URL(fileURLWithPath: suggested).deletingPathExtension().lastPathComponent
            let name = String(stem.prefix(120)) + "." + image.fileExtension
            if let output = try? NodebayManagedFileStorage.uniqueOutputURL(for: .media, suggestedName: name) {
                do {
                    try image.data.write(to: output, options: .atomic)
                    if let bookmark = createBookmark(for: output) {
                        return [await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)]
                    }
                } catch {
                    NSLog("Nodebay could not save a dropped image (%@)", (error as NSError).domain)
                }
                NodebayManagedFileStorage.removeFailedOutput(at: output, category: .media)
            }
            return []
        }

        // Explicit image content that failed validation must not re-enter the
        // generic data path and become an unchecked file (or a misleading link).
        if !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return []
        }

        if let droppedFile = await provider.extractDroppedFileReference() {
            let bookmark = Bookmark(data: droppedFile.bookmarkData)
            if let accessibleURL = bookmark.resolvedURL {
                let didStartAccessing = accessibleURL.startAccessingSecurityScopedResource()
                let internetURL = internetShortcutURL(at: accessibleURL)
                if didStartAccessing {
                    accessibleURL.stopAccessingSecurityScopedResource()
                }
                if let internetURL {
                    return [await ShelfItem(kind: .link(url: internetURL), isTemporary: false)]
                }
            }
            return [await ShelfItem(kind: .file(bookmark: droppedFile.bookmarkData), isTemporary: false)]
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let internetURL = internetShortcutURL(at: url) {
                    return [await ShelfItem(kind: .link(url: internetURL), isTemporary: false)]
                }
                if let bookmark = createBookmark(for: url) {
                    return [await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)]
                }
            } else {
                return [await ShelfItem(kind: .link(url: url), isTemporary: false)]
            }
            return []
        }
        
        if let text = await provider.extractText() {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let urls = lines.compactMap { try? MediaDownloaderService.validatedURL(from: $0) }
            if !urls.isEmpty, urls.count == lines.count {
                var items: [ShelfItem] = []
                for url in urls {
                    items.append(await ShelfItem(kind: .link(url: url), isTemporary: false))
                }
                return items
            }
            return [await ShelfItem(kind: .text(string: text), isTemporary: false)]
        }
        
        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return [await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)]
            }
            return []
        }
        
        return []
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }

    private static func internetShortcutURL(at fileURL: URL) -> URL? {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "url" || ext == "webloc",
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count <= 1_048_576 else { return nil }
        if ext == "webloc",
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let raw = plist["URL"] as? String {
            return try? MediaDownloaderService.validatedURL(from: raw)
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let raw = text.components(separatedBy: .newlines)
            .first { $0.range(of: "URL=", options: [.caseInsensitive, .anchored]) != nil }?
            .dropFirst(4).description
        return raw.flatMap { try? MediaDownloaderService.validatedURL(from: $0) }
    }
}
