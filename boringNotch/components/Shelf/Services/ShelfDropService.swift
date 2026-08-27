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
        if let actualFileURL = await provider.extractFileURL() {
            if let internetURL = internetShortcutURL(at: actualFileURL) {
                return [await ShelfItem(kind: .link(url: internetURL), isTemporary: false)]
            }
            if let bookmark = createBookmark(for: actualFileURL) {
                return [await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)]
            }
            return []
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
        
        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return [await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)]
            }
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
