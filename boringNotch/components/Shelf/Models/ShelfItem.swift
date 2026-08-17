//
//  ShelfItem.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation

indirect enum ShelfItemKind: Codable, Equatable, Sendable {
    case file(bookmark: Data)
    case text(string: String)
    case link(url: URL)
    case stack(name: String, members: [ShelfItem])

    enum CodingKeys: String, CodingKey { case type, value, name, members }

    enum KindTag: String, Codable { case file, text, link, stack }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .file:
            let data = try container.decode(Data.self, forKey: .value)
            self = .file(bookmark: data)
        case .text:
            self = .text(string: try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(url: try container.decode(URL.self, forKey: .value))
        case .stack:
            self = .stack(
                name: try container.decode(String.self, forKey: .name),
                members: try container.decode([ShelfItem].self, forKey: .members)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let bookmark):
            try container.encode(KindTag.file, forKey: .type)
            try container.encode(bookmark, forKey: .value)
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        case .stack(let name, let members):
            try container.encode(KindTag.stack, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(members, forKey: .members)
        }
    }

}

@MainActor
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: ShelfItemKind
    let isTemporary: Bool
    init(id: UUID = UUID(), kind: ShelfItemKind, isTemporary: Bool = false) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
    }

    var displayName: String {
        switch kind {
        case .file(let bookmarkData):
            let bookmark = Bookmark(data: bookmarkData)
            guard let resolvedURL = bookmark.resolvedURL else { return "" }
            
            // Check for stored data files (text blocks, weblocs, etc.) to provide friendly names
            if resolvedURL.pathExtension.lowercased() == "json" && resolvedURL.path.contains("TextBlocks") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    struct TextBlockData: Codable {
                        let content: String
                        let title: String?
                        var displayTitle: String {
                            if let title = title, !title.isEmpty {
                                return title
                            }
                            let firstLine = content.components(separatedBy: .newlines).first ?? content
                            if firstLine.count > 50 {
                                return String(firstLine.prefix(47)) + "..."
                            }
                            return firstLine
                        }
                    }
                    if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                        return textData.displayTitle
                    }
                } catch {
                    // Fall through to default naming
                }
            } else if resolvedURL.pathExtension.lowercased() == "webloc" && resolvedURL.path.contains("WebLocs") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let urlString = plist["URL"] as? String {
                        let title = plist["Title"] as? String
                        return title ?? urlString
                    }
                } catch {
                    // Fall through to default naming
                }
            }
            return (try? resolvedURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? resolvedURL.lastPathComponent
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url):
            let s = url.absoluteString
            if s.hasPrefix("https://") {
                return String(s.dropFirst("https://".count))
            } else if s.hasPrefix("http://") {
                return String(s.dropFirst("http://".count))
            } else {
                return s
            }
        case .stack(let name, let members):
            return name.isEmpty ? "\(members.count) files" : name
        }
    }
    
    var fileURL: URL? {
        guard case let .file(bookmarkData) = kind else { return nil }
        return Bookmark(data: bookmarkData).resolvedURL
    }
    
    var URL: URL? {
        switch kind {
        case .file(let bookmarkData):
            return Bookmark(data: bookmarkData).resolvedURL
        case .link(let url):
            return url
        case .text:
            return nil
        case .stack:
            return nil
        }
    }
    
    var icon: NSImage {
        if case .stack(_, let members) = kind {
            return Self.stackIcon(members: members)
        }
        guard case .file = kind else {
            return Self.thumbnailSymbolImage(systemName: kind.iconSymbolName) ?? NSImage()
        }
        if let resolvedURL = fileURL {
            return NSWorkspace.shared.icon(forFile: resolvedURL.path)
        }
        return NSImage()
    }
    

    func cleanupStoredData() {
        guard case let .file(bookmarkData) = kind,
              let url = Bookmark(data: bookmarkData).resolvedURL else { return }
        
        // Handle temporary files
        if isTemporary {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            return
        }
    }

    var stackMembers: [ShelfItem]? {
        guard case .stack(_, let members) = kind else { return nil }
        return members
    }

    var flattenedItems: [ShelfItem] {
        stackMembers ?? [self]
    }
}

private extension ShelfItem {
   static func stackIcon(members: [ShelfItem]) -> NSImage {
        let size = CGSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let cards = min(3, max(1, members.count))
        for index in 0..<cards {
            let inset = CGFloat(cards - index - 1) * 5
            let rect = CGRect(x: inset, y: inset, width: 52, height: 52)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        return image
    }

   static func thumbnailSymbolImage(
        systemName: String,
    size: CGSize = CGSize(width: 64, height: 80), 
    symbolPointSize: CGFloat = 38,
    backgroundColor: NSColor = NSColor.white,
    symbolColor: NSColor = NSColor.labelColor
    ) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = min(size.width, size.height) * 0.06
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        if let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let symbolSize = CGSize(width: symbolPointSize, height: symbolPointSize)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            let symbolRect = CGRect(origin: symbolOrigin, size: symbolSize)
            symbol.draw(in: symbolRect)
        }

        return image
    }
}

// MARK: - Identity key for deduplication
extension ShelfItem {
    var identityKey: String {
        switch kind {
        case .file(let bookmarkData):
            if let url = Bookmark(data: bookmarkData).resolvedURL {
                return "file://" + url.standardizedFileURL.path
            }
            return "file://missing/" + bookmarkData.base64EncodedString()
        case .link(let u):
            return "link://" + u.absoluteString
        case .text(let s):
            return "text://" + s
        case .stack:
            return "stack://" + id.uuidString
        }
    }
}

// MARK: - Private helpers
private extension ShelfItemKind {
    var iconSymbolName: String {
        switch self {
        case .file:
            return "questionmark.circle"
        case .text:
            return "text.justifyleft"
        case .link:
            return "link"
        case .stack:
            return "square.stack.3d.up.fill"
        }
    }
}

