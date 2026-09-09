//
//  ShelfPersistenceService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation

// Access model types
@_exported import struct Foundation.URL


// The serial IO queue owns both codecs and all access to the persistence file.
final class ShelfPersistenceService: @unchecked Sendable {
    static let shared = ShelfPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let persistenceQueue = DispatchQueue(label: "space.nodebay.shelf-persistence", qos: .utility)

    private convenience init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let supportRoot = support ?? fm.temporaryDirectory
        let legacyDir = supportRoot.appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        let dir = supportRoot.appendingPathComponent("Nodebay", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("items.json")
        let legacyFileURL = legacyDir.appendingPathComponent("items.json")
        if !fm.fileExists(atPath: fileURL.path), fm.fileExists(atPath: legacyFileURL.path) {
            // Copy, never move or delete, so rollback to Boring Notch is safe.
            try? fm.copyItem(at: legacyFileURL, to: fileURL)
        }
        self.init(fileURL: fileURL)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [ShelfItem] {
        persistenceQueue.sync { loadStoredItems() }
    }

    private func loadStoredItems() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        
        // Try to decode as array first (normal case)
        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }
        
        // If array decoding fails, try to decode individual items
        do {
            // Parse as JSON array to get individual item data
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                print("⚠️ Shelf persistence file is not a valid JSON array")
                return []
            }
            
            var validItems: [ShelfItem] = []
            var failedCount = 0
            
            for (index, jsonItem) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    let item = try decoder.decode(ShelfItem.self, from: itemData)
                    validItems.append(item)
                } catch {
                    failedCount += 1
                    print("⚠️ Failed to decode shelf item at index \(index): \(error.localizedDescription)")
                }
            }
            
            if failedCount > 0 {
                print("📦 Successfully loaded \(validItems.count) shelf items, discarded \(failedCount) corrupted items")
            }
            
            return validItems
        } catch {
            print("❌ Failed to parse shelf persistence file: \(error.localizedDescription)")
            return []
        }
    }

    /// A final save is also a barrier for every previously admitted async save.
    /// IO never waits on MainActor, so this can safely run during termination.
    @MainActor
    func save(_ items: [ShelfItem]) {
        persistenceQueue.sync { write(items) }
    }

    private func write(_ items: [ShelfItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        } catch {
            print("Failed to save shelf items: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func saveAsync(_ items: [ShelfItem]) async {
        // Enqueue before the first suspension on the same actor that captures
        // shelf snapshots and flushes them. Cancellation does not reorder an
        // admitted write behind a newer flush or leave a continuation pending.
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                self.write(items)
                continuation.resume()
            }
        }
    }
}
