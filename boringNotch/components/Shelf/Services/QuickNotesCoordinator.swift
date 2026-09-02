import AppKit
import Combine
import Foundation

struct QuickNoteDiagnostic: Codable {
    let succeeded: Bool
    let characterCount: Int
    let representation: String
    let locationCategory: String
    let error: String?
}

@MainActor final class QuickNotesCoordinator: ObservableObject {
    static let shared = QuickNotesCoordinator()
    @Published private(set) var isWorking = false
    @Published private(set) var notice: String?
    @Published private(set) var lastCreatedID: UUID?
    @Published private(set) var diagnostic: QuickNoteDiagnostic?
    private var noticeTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    var enabled: Bool { defaults.object(forKey: "nodebay.quickNotes.enabled") as? Bool ?? true }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodebay/Quick Notes", isDirectory: true)
    }

    private init() {
        if let data = defaults.data(forKey: "nodebay.quickNotes.diagnostic") {
            diagnostic = try? JSONDecoder().decode(QuickNoteDiagnostic.self, from: data)
        }
    }

    /// Called only for an explicit, eligible Command-V. No timer, change-count
    /// observer or other background clipboard access exists.
    func pasteIfSupported() -> Bool {
        let board = NSPasteboard.general
        let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let text = board.string(forType: .string) ?? board.string(forType: .URL)
        let rich = defaults.object(forKey: "nodebay.quickNotes.richText") as? Bool ?? true
        let snapshot = QuickNoteClipboard(text: text,
            html: enabled && rich ? board.data(forType: .html) : nil,
            rtf: enabled && rich ? board.data(forType: .rtf) : nil, fileURLs: files)
        if !enabled {
            // Without Quick Notes, ordinary prose must retain native paste behavior.
            guard !files.isEmpty || (text?.utf8.count ?? 0) <= 65_536 else { return false }
            if case .unhandled = ShelfPasteRoute.decide(snapshot, notesEnabled: false) { return false }
        }
        guard !files.isEmpty || snapshot.html != nil || snapshot.rtf != nil ||
                text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        submit(snapshot, forceNote: false)
        return true
    }

    func saveText(_ text: String, completion: @escaping (Bool) -> Void) {
        guard enabled else { completion(false); return }
        submit(.init(text: text), forceNote: true, completion: completion)
    }

    private func submit(_ snapshot: QuickNoteClipboard, forceNote: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !isWorking else { showNotice(QuickNoteError.busy.rawValue); completion?(false); return }
        isWorking = true
        SharingStateManager.shared.beginInteraction()
        let options = QuickNoteOptions(
            preferHeading: defaults.bool(forKey: "nodebay.quickNotes.preferHeading"),
            preserveRichText: defaults.object(forKey: "nodebay.quickNotes.richText") as? Bool ?? true,
            compactFilename: defaults.string(forKey: "nodebay.quickNotes.filenameStyle") == "Compact timestamp")
        let shouldAdd = defaults.object(forKey: "nodebay.quickNotes.addToShelf") as? Bool ?? true
        let notesEnabled = enabled
        Task {
            defer { isWorking = false; SharingStateManager.shared.endInteraction() }
            let route = await Task.detached {
                if forceNote || (snapshot.text?.utf8.count ?? 0) > QuickNoteText.maximumTextBytes ||
                    (snapshot.html?.count ?? 0) > QuickNoteText.maximumRichBytes ||
                    (snapshot.rtf?.count ?? 0) > QuickNoteText.maximumRichBytes { return ShelfPasteRoute.note }
                return ShelfPasteRoute.decide(snapshot, notesEnabled: notesEnabled)
            }.value
            switch route {
            case .files(let urls):
                let providers = urls.map { NSItemProvider(object: $0 as NSURL) }
                let items = await ShelfDropService.items(from: providers)
                ShelfStateViewModel.shared.add(items)
                if let item = items.last { lastCreatedID = item.id }
            case .downloads(let urls): DownloadCoordinator.shared.add(urls: urls)
            case .unhandled: completion?(false)
            case .note:
                do {
                    let result = try await QuickNoteService.shared.create(snapshot, options: options, directory: Self.directory)
                    if shouldAdd {
                        let item = ShelfItem(kind: .file(bookmark: try Bookmark(url: result.url).data))
                        ShelfStateViewModel.shared.add([item])
                        ShelfSelectionModel.shared.selectSingle(item)
                        lastCreatedID = item.id
                    }
                    record(.init(succeeded: true, characterCount: result.characterCount, representation: result.representation, locationCategory: "Nodebay-managed Quick Notes", error: nil))
                    let confirms = defaults.object(forKey: "nodebay.quickNotes.confirmation") as? Bool ?? true
                    showNotice(confirms ? (shouldAdd ? "Quick Note added" : "Quick Note saved") : nil)
                    completion?(true)
                } catch {
                    let message = (error as? QuickNoteError)?.rawValue ?? QuickNoteError.storage.rawValue
                    record(.init(succeeded: false, characterCount: 0, representation: "Unavailable", locationCategory: "Nodebay-managed Quick Notes", error: message))
                    showNotice(message)
                    completion?(false)
                }
            }
        }
    }

    private func record(_ value: QuickNoteDiagnostic) {
        diagnostic = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "nodebay.quickNotes.diagnostic") }
    }

    func dismissNotice() { noticeTask?.cancel(); noticeTask = nil; notice = nil }

    private func showNotice(_ message: String?) {
        dismissNotice()
        notice = message
        // Keep the result visible briefly even if the pointer moves away during
        // the asynchronous write. This task contains no clipboard contents.
        SharingStateManager.shared.beginInteraction()
        noticeTask = Task { [weak self] in
            defer { SharingStateManager.shared.endInteraction() }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.notice = nil
        }
    }
}
