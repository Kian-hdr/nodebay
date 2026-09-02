import AppKit
import SwiftUI

enum EngineAvailability { case installed, unavailable, error }
struct EngineDiagnostic {
    let availability: EngineAvailability; let version, location, message: String
    static func unavailable(_ s: String) -> Self { .init(availability: .unavailable, version: "", location: "", message: s) }
}
struct ProcessingProviderDescriptor {
    let id, name, systemImage, purpose, provider: String; let officialURL: URL
    let license: String; let runsLocally, requiresNetwork: Bool; let inputTypes, outputTypes: [String]
    let pinnedVersion: String?; let configurable: Bool
}
protocol ProcessingProvider {}
struct Bookmark { let data: Data; init(url: URL) throws { data = Data(url.absoluteString.utf8) } }
struct ShelfItem: Identifiable {
    indirect enum Kind { case file(bookmark: Data), stack(name: String, members: [ShelfItem]) }
    let id = UUID(); let kind: Kind
    var fileURL: URL? { if case .file(let b) = kind { return URL(string: String(decoding: b, as: UTF8.self)) }; return nil }
    var stackMembers: [ShelfItem]? { if case .stack(_, let m) = kind { return m }; return nil }
    var displayName: String { fileURL?.lastPathComponent ?? "Models" }
}
@MainActor final class ShelfStateViewModel {
    static let shared = ShelfStateViewModel(); var items: [ShelfItem] = []
    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? { item.fileURL }
    func add(_ values: [ShelfItem]) { items += values }
    func insertResult(_ result: ShelfItem, beside source: ShelfItem) { items.insert(result, at: (items.firstIndex { $0.id == source.id } ?? 0) + 1) }
}
@MainActor final class SharingStateManager {
    static let shared = SharingStateManager()
    func beginInteraction() {}; func endInteraction() {}
}
@main enum CoordinatorHarness {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[3])
        let good = ShelfItem(kind: .file(bookmark: try Bookmark(url: URL(fileURLWithPath: CommandLine.arguments[2])).data))
        let badURL = root.deletingLastPathComponent().appendingPathComponent("bad.stl")
        try Data("malformed".utf8).write(to: badURL)
        let bad = ShelfItem(kind: .file(bookmark: try Bookmark(url: badURL).data))
        let unsupported = ShelfItem(kind: .file(bookmark: try Bookmark(url: root.appendingPathComponent("skip.txt")).data))
        let members = [good, bad, unsupported]
        let source = ShelfItem(kind: .stack(name: "Sources", members: members))
        let shelf = ShelfStateViewModel.shared; shelf.items = [source]
        let suite = "nodebay.stl-test.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = STLRepairCoordinator(service: STLRepairService(root: root), defaults: defaults)
        coordinator.start(items: members, beside: source, mode: .safe, automatic: true)
        for _ in 0..<1000 { if !coordinator.isRunning { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(!coordinator.isRunning)
        precondition(coordinator.entries.count == 2 && coordinator.entries[1].error != nil)
        precondition(coordinator.progress.contains("1 unsupported skipped"))
        precondition(shelf.items.count == 2 && shelf.items[0].id == source.id)
        precondition(shelf.items[0].stackMembers?.count == 3 && shelf.items[1].stackMembers?.count == 1)
        let output = shelf.items[1].stackMembers![0].fileURL!
        precondition(FileManager.default.fileExists(atPath: output.path))
        shelf.items.removeLast()
        precondition(FileManager.default.fileExists(atPath: output.path))
        print("STL batch partial-success fixtures passed")
    }
}
