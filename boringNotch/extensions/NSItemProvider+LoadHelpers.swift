//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

struct DroppedFileReference: Sendable {
    let url: URL
    let bookmarkData: Data
}

extension NSItemProvider {
    /// Captures a persistent bookmark while the item-provider completion
    /// handler still owns the drag's temporary sandbox extension. This is
    /// required for files on external volumes, whose transient access may be
    /// revoked before an asynchronously returned URL is used by the shelf.
    func extractDroppedFileReference() async -> DroppedFileReference? {
        let identifiers = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.item.identifier,
        ]

        for identifier in identifiers where hasItemConformingToTypeIdentifier(identifier) {
            if let reference = await loadDroppedFileReference(typeIdentifier: identifier) {
                return reference
            }
        }
        return nil
    }

    private func loadDroppedFileReference(typeIdentifier: String) async -> DroppedFileReference? {
        await withCheckedContinuation { (continuation: CheckedContinuation<DroppedFileReference?, Never>) in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                guard error == nil,
                      let url = Self.fileURL(fromProviderItem: item),
                      url.isFileURL else {
                    continuation.resume(returning: nil)
                    return
                }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let bookmark = try Bookmark(url: url)
                    continuation.resume(
                        returning: DroppedFileReference(url: url, bookmarkData: bookmark.data)
                    )
                } catch {
                    NSLog(
                        "Nodebay could not retain a dropped file reference (%@:%ld)",
                        (error as NSError).domain,
                        (error as NSError).code
                    )
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        NSLog(String(describing: self.registeredTypeIdentifiers))
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    if !url.absoluteString.contains("com.apple.SwiftUI.filePromises") {
                        cont.resume(returning: nil)
                        return
                    }
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent
                    
                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()

                    do {
                        // Delete the file first
                        try fileManager.removeItem(at: url)
                        print("Deleted file: \(url.path)")

                        // Check folder contents
                        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                        if contents.isEmpty {
                            try fileManager.removeItem(at: folderURL)
                            print("Folder was empty, deleted folder: \(folderURL.path)")
                        } else {
                            print("Folder not deleted — it still contains \(contents.count) item(s).")
                        }

                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                    
                    cont.resume(returning: data)
                } else if let data = item as? Data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.fileURL(fromProviderItem: item))
            }
        }
    }

    private static func fileURL(fromProviderItem item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url.standardizedFileURL : nil
        }
        if let string = item as? String {
            return fileURL(fromProviderString: string)
        }
        if let data = item as? Data {
            if let string = String(data: data, encoding: .utf8),
               let url = fileURL(fromProviderString: string) {
                return url
            }
            return Bookmark(data: data).resolvedURL?.standardizedFileURL
        }
        return nil
    }

    private static func fileURL(fromProviderString value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL
        }
        guard let url = URL(string: value), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            cont.resume(returning: url)
                            return
                        } else if string.hasPrefix("/") {
                            cont.resume(returning: URL(fileURLWithPath: string))
                            return
                        }
                    }
                    cont.resume(returning: nil)
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        cont.resume(returning: url)
                    } else if string.hasPrefix("/") {
                        cont.resume(returning: URL(fileURLWithPath: string))
                    } else {
                        cont.resume(returning: nil)
                    }
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
