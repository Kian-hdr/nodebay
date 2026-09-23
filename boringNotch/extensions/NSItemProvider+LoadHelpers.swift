//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers
import ImageIO

struct DroppedFileReference: Sendable {
    let url: URL
    let bookmarkData: Data
}

/// A provider may finish after the drag ended or never call back. Resolve exactly
/// once so a broken browser provider cannot keep a shelf import pending forever.
private final class DroppedImageLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

    @discardableResult
    func finish(_ data: Data?) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: data)
        return pending != nil
    }
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
    
    /// Browser image drags can advertise both image bytes and the enclosing page URL.
    /// Consume an explicit image representation before considering the URL.
    func extractDroppedImage() async -> (data: Data, fileExtension: String)? {
        let identifiers = registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .image) == true
        }
        for identifier in identifiers {
            let data: Data? = await withCheckedContinuation { continuation in
                let completion = DroppedImageLoad(continuation)
                let progress = loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                    completion.finish(error == nil ? data : nil)
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) {
                    if completion.finish(nil) { progress.cancel() }
                }
            }
            if let data, let ext = Self.validatedImageExtension(for: data) {
                return (data, ext)
            }
        }
        return nil
    }

    /// Validate the actual encoded format and dimensions before decoding. Never trust
    /// the browser's filename or advertised type for a generated shelf file.
    static func validatedImageExtension(for data: Data) -> String? {
        guard !data.isEmpty, data.count <= 32 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image),
              let ext = type.preferredFilenameExtension,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 40_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil
        else { return nil }
        return ext
    }

    /// Reads a provider-owned file without changing it. Its lifetime belongs to
    /// the source application, even when it resides in a temporary directory.
    func loadData() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                if let url = item as? URL, url.isFileURL {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    guard let handle = try? FileHandle(forReadingFrom: url) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    defer { try? handle.close() }
                    let data = try? handle.read(upToCount: 32 * 1_024 * 1_024 + 1)
                    continuation.resume(returning: data.flatMap { $0.count <= 32 * 1_024 * 1_024 ? $0 : nil })
                } else if let data = item as? Data, data.count <= 32 * 1_024 * 1_024 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
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
