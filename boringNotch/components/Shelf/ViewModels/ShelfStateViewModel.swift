//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { schedulePersistence() }
    }

    @Published var isLoading: Bool = false
    @Published private(set) var convertingItemIDs: Set<ShelfItem.ID> = []
    @Published private(set) var conversionProgress: [ShelfItem.ID: String] = [:]
    @Published private(set) var canUndoRemoval = false

    private var lastRemoval: (item: ShelfItem, index: Int)?
    private var removalNoticeDismissTask: Task<Void, Never>?
    private let removalNoticeDuration: Duration = .seconds(4)

    var isEmpty: Bool { items.isEmpty }

    // Debounced persistence
    private var persistenceTask: Task<Void, Never>?
    private let persistenceDelay: Duration = .seconds(1)

    func isConverting(_ item: ShelfItem) -> Bool {
        convertingItemIDs.contains(item.id)
    }

    func beginConverting(_ items: [ShelfItem]) {
        convertingItemIDs.formUnion(items.map(\.id))
    }

    func finishConverting(_ items: [ShelfItem], preservingProgressForFailures: Bool = false) {
        convertingItemIDs.subtract(items.map(\.id))
        if !preservingProgressForFailures {
            for item in items { conversionProgress[item.id] = nil }
        }
    }

    func setConversionProgress(_ text: String, for item: ShelfItem) {
        conversionProgress[item.id] = text
    }

    private init() {
        items = ShelfPersistenceService.shared.load().map(Self.migrateLegacyTemporaryMarkdown)
    }

    /// Older Nodebay builds stored generated Markdown in the temporary folder
    /// and exported it as a file promise. Copy those results into durable
    /// app-owned storage once, preserving shelf identity and stack membership.
    private static func migrateLegacyTemporaryMarkdown(_ item: ShelfItem) -> ShelfItem {
        switch item.kind {
        case .file(let bookmarkData):
            guard item.isTemporary,
                  let sourceURL = Bookmark(data: bookmarkData).resolvedURL,
                  ["md", "markdown"].contains(sourceURL.pathExtension.lowercased()),
                  let outputURL = try? NodebayManagedFileStorage.persistentMarkdownCopy(of: sourceURL),
                  let bookmark = try? Bookmark(url: outputURL) else {
                return item
            }
            return ShelfItem(id: item.id, kind: .file(bookmark: bookmark.data), isTemporary: false)

        case .stack(let name, let members):
            let migratedMembers = members.map(migrateLegacyTemporaryMarkdown)
            guard migratedMembers != members else { return item }
            return ShelfItem(
                id: item.id,
                kind: .stack(name: name, members: migratedMembers),
                isTemporary: item.isTemporary
            )

        case .link, .text:
            return item
        }
    }
    
    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.persistenceDelay ?? .seconds(1))
            guard let self = self, !Task.isCancelled else { return }
            await ShelfPersistenceService.shared.saveAsync(self.items)
        }
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        let originalKeys = Set(items.map(\.identityKey))
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
        if UserDefaults.standard.bool(forKey: "nodebay.stlRepair.automatic"), !STLRepairCoordinator.shared.isRunning {
            let added = newItems.filter { !originalKeys.contains($0.identityKey) }.flatMap { $0.stackMembers ?? [$0] }
            STLRepairCoordinator.shared.start(items: added, beside: nil, mode: .safe, automatic: true)
        }
    }

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        lastRemoval = (item, index)
        items.removeAll { $0.id == item.id }
        canUndoRemoval = true
        scheduleRemovalNoticeDismissal()
    }

    func undoLastRemoval() {
        guard let removal = lastRemoval else { return }
        removalNoticeDismissTask?.cancel()
        removalNoticeDismissTask = nil
        let index = min(removal.index, items.count)
        items.insert(removal.item, at: index)
        lastRemoval = nil
        canUndoRemoval = false
    }

    func dismissRemovalNotice() {
        removalNoticeDismissTask?.cancel()
        removalNoticeDismissTask = nil
        lastRemoval = nil
        canUndoRemoval = false
    }

    private func scheduleRemovalNoticeDismissal() {
        removalNoticeDismissTask?.cancel()
        removalNoticeDismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.removalNoticeDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.dismissRemovalNotice()
        }
    }

    @discardableResult
    func createStack(from selectedItems: [ShelfItem], name: String? = nil) -> ShelfItem? {
        let selectedIDs = Set(selectedItems.map(\.id))
        guard selectedIDs.count >= 2,
              let insertionIndex = items.indices.first(where: { selectedIDs.contains(items[$0].id) }) else {
            return nil
        }
        let members = items
            .filter { selectedIDs.contains($0.id) }
            .flatMap(\.flattenedItems)
            .reduce(into: [ShelfItem]()) { result, member in
                if !result.contains(where: { $0.identityKey == member.identityKey }) {
                    result.append(member)
                }
            }
        guard members.count >= 2 else { return nil }

        let stack = ShelfItem(
            kind: .stack(name: name ?? "File Stack", members: members),
            isTemporary: false
        )
        items.removeAll { selectedIDs.contains($0.id) }
        items.insert(stack, at: min(insertionIndex, items.count))
        ShelfSelectionModel.shared.selectSingle(stack)
        return stack
    }

    @discardableResult
    func createStack(onto target: ShelfItem, droppedItems: [ShelfItem]) -> ShelfItem? {
        guard let insertionIndex = items.firstIndex(where: { $0.id == target.id }) else { return nil }
        let members = (target.flattenedItems + droppedItems.flatMap(\.flattenedItems))
            .reduce(into: [ShelfItem]()) { result, member in
                if !result.contains(where: { $0.identityKey == member.identityKey }) {
                    result.append(member)
                }
            }
        guard members.count >= 2 else { return nil }
        let memberKeys = Set(members.map(\.identityKey))
        items.removeAll { item in
            item.id == target.id || (item.stackMembers == nil && memberKeys.contains(item.identityKey))
        }
        let stack = ShelfItem(kind: .stack(name: "File Stack", members: members))
        items.insert(stack, at: min(insertionIndex, items.count))
        ShelfSelectionModel.shared.selectSingle(stack)
        return stack
    }

    func renameStack(_ stack: ShelfItem, name: String) {
        guard let index = items.firstIndex(where: { $0.id == stack.id }),
              case .stack(_, let members) = items[index].kind else { return }
        items[index] = ShelfItem(id: stack.id, kind: .stack(name: name, members: members))
    }

    func reorderMember(in stack: ShelfItem, from source: Int, to destination: Int) {
        guard let index = items.firstIndex(where: { $0.id == stack.id }),
              case .stack(let name, var members) = items[index].kind,
              members.indices.contains(source), members.indices.contains(destination), source != destination else { return }
        let member = members.remove(at: source)
        members.insert(member, at: destination)
        items[index] = ShelfItem(id: stack.id, kind: .stack(name: name, members: members))
    }

    func removeMember(_ member: ShelfItem, from stack: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == stack.id }),
              case .stack(let name, var members) = items[index].kind else { return }
        members.removeAll { $0.id == member.id }
        if members.count < 2 {
            items.remove(at: index)
            items.insert(contentsOf: members + [member], at: index)
        } else {
            items[index] = ShelfItem(id: stack.id, kind: .stack(name: name, members: members))
            items.insert(member, at: min(index + 1, items.count))
        }
    }

    func dissolveStack(_ stack: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == stack.id }),
              case .stack(_, let members) = items[index].kind else { return }
        items.remove(at: index)
        items.insert(contentsOf: members, at: index)
    }

    func insertResultStack(_ result: ShelfItem, beside source: ShelfItem) {
        insertResult(result, beside: source)
    }

    func insertResult(_ result: ShelfItem, beside source: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == source.id }) else {
            add([result])
            return
        }
        items.insert(result, at: min(index + 1, items.count))
    }

    /// Replaces only the shelf reference. Files on disk are never moved or deleted.
    func replaceReference(_ source: ShelfItem, with replacements: [ShelfItem]) {
        guard !replacements.isEmpty,
              let sourceIndex = items.firstIndex(where: { $0.id == source.id }) else {
            add(replacements)
            return
        }

        var seen = Set(items.enumerated().compactMap { index, item in
            index == sourceIndex ? nil : item.identityKey
        })
        let uniqueReplacements = replacements.filter { replacement in
            seen.insert(replacement.identityKey).inserted
        }
        items.replaceSubrange(sourceIndex...sourceIndex, with: uniqueReplacements)
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx] = ShelfItem(kind: .file(bookmark: bookmark), isTemporary:  items[idx].isTemporary)
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            guard let self else { return }
            self.add(dropped)
            self.isLoading = false

            // A dropped HTTP(S) link is routed through the one shared download
            // coordinator. This prevents duplicate jobs when multiple notch
            // windows display the same shelf.
            let droppedMediaLinks = dropped.compactMap { item -> ShelfItem? in
                guard case .link(let url) = item.kind else { return nil }
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
                return self.items.first(where: { $0.identityKey == item.identityKey })
            }
            DownloadCoordinator.shared.start(items: droppedMediaLinks)
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                case .stack(let name, let members):
                    var validMembers: [ShelfItem] = []
                    for member in members {
                        if case .file(let data) = member.kind {
                            if await Bookmark(data: data).validate() { validMembers.append(member) }
                        } else {
                            validMembers.append(member)
                        }
                    }
                    if validMembers.count >= 2 {
                        keep.append(ShelfItem(id: item.id, kind: .stack(name: name, members: validMembers)))
                    } else {
                        keep.append(contentsOf: validMembers)
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }


    /// Resolves the file URL for an item and updates the bookmark if stale.
    /// Use this for user-initiated actions where bookmark refresh is desired.
    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        items.compactMap { $0.fileURL }
    }

    @MainActor
    func flushSync() {
        // Cancel any scheduled persistence task (we'll save synchronously now)
        persistenceTask?.cancel()
        persistenceTask = nil

        // Perform a synchronous, atomic save to disk
        ShelfPersistenceService.shared.save(self.items)
    }
}
