import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODEL = ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift"


class ShelfActivityTests(unittest.TestCase):
    def test_overlapping_imports_stay_busy_through_download_handoff(self):
        source = MODEL.read_text()
        load = "    func load(" + source.split("    func load(", 1)[1].split(
            "    func cleanupInvalidItems()", 1
        )[0]
        properties = source.split("    @Published var isLoading:", 1)[1].split(
            "    @Published private(set) var convertingItemIDs", 1
        )[0]
        properties = "    var isLoading:" + properties
        fixture = '''import Foundation
struct NSItemProvider: Sendable { let id: Int }
struct ShelfItem: Sendable {
    enum Kind: Sendable { case link(URL) }
    let kind: Kind
    var identityKey: String { switch kind { case .link(let url): return url.absoluteString } }
}
actor DropGate {
    static let shared = DropGate()
    var waiting: [Int: CheckedContinuation<[ShelfItem], Never>] = [:]
    func items(_ id: Int) async -> [ShelfItem] {
        await withCheckedContinuation { waiting[id] = $0 }
    }
    func count() -> Int { waiting.count }
    func finish(_ id: Int) {
        waiting.removeValue(forKey: id)?.resume(returning: [
            ShelfItem(kind: .link(URL(string: "https://example.com/\\(id)")!))
        ])
    }
}
struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        await DropGate.shared.items(providers[0].id)
    }
}
@MainActor final class DownloadCoordinator {
    static let shared = DownloadCoordinator()
    weak var observedShelf: ShelfStateViewModel?
    var started: [ShelfItem] = []
    var busyAtHandoff: [Bool] = []
    func start(items: [ShelfItem]) {
        started.append(contentsOf: items)
        busyAtHandoff.append(observedShelf?.isLoading == true)
    }
}
@MainActor final class ShelfStateViewModel {
    var items: [ShelfItem] = []
    func add(_ items: [ShelfItem]) { self.items.append(contentsOf: items) }
''' + properties + load + "}\n" + '''
@main struct Main {
    @MainActor static func main() async {
        let shelf = ShelfStateViewModel()
        let downloads = DownloadCoordinator.shared
        downloads.observedShelf = shelf
        shelf.load([])
        precondition(!shelf.isLoading, "Empty drop must not register work")
        for order in [[1, 2], [4, 3]] {
            let initialCount = shelf.items.count
            shelf.load([NSItemProvider(id: order[0])])
            shelf.load([NSItemProvider(id: order[1])])
            precondition(shelf.isLoading, "Import must be busy before Task begins")
            while await DropGate.shared.count() < 2 { await Task.yield() }
            await DropGate.shared.finish(order[0])
            while shelf.items.count < initialCount + 1 { await Task.yield() }
            precondition(shelf.isLoading, "First completed import cleared busy state while second import remains")
            await DropGate.shared.finish(order[1])
            while shelf.items.count < initialCount + 2 { await Task.yield() }
            precondition(!shelf.isLoading, "All completed imports must release busy state")
        }
        precondition(downloads.started.count == 4, "Every imported link must reach downloader")
        precondition(downloads.busyAtHandoff.allSatisfy { $0 }, "Import remains active until download handoff")
        print("Overlapping shelf import checks passed")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = pathlib.Path(directory)
            (folder / "Harness.swift").write_text(fixture)
            executable = folder / "shelf-activity"
            compiled = subprocess.run(
                ["swiftc", "-parse-as-library", str(folder / "Harness.swift"), "-o", str(executable)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(executable)], timeout=20, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Overlapping shelf import checks passed", result.stdout)

    def test_overlapping_conversions_count_each_distinct_item_per_operation(self):
        source = MODEL.read_text()
        properties = "    var convertingItemIDs:" + source.split(
            "    @Published private(set) var convertingItemIDs:", 1
        )[1].split("    @Published private(set) var canUndoRemoval", 1)[0]
        properties = properties.replace("@Published private(set) ", "")
        methods = "    func isConverting(" + source.split("    func isConverting(", 1)[1].split(
            "    private init()", 1
        )[0]
        fixture = '''import Foundation
struct ShelfItem { typealias ID = UUID; let id = UUID() }
@MainActor final class ShelfStateViewModel {
''' + properties + methods + "}\n" + '''
@main struct Main {
    @MainActor static func main() {
        let shelf = ShelfStateViewModel()
        let a = ShelfItem(), b = ShelfItem(), c = ShelfItem()
        shelf.beginConverting([a, a, b])
        shelf.setConversionProgress("Working", for: a)
        shelf.setConversionProgress("Working", for: b)
        shelf.beginConverting([a, c])
        shelf.finishConverting([a, a, b])
        precondition(shelf.convertingItemIDs == Set([a.id, c.id]), "First completion must not clear another operation's items")
        precondition(shelf.conversionProgress[a.id] == "Working", "Overlapping progress must remain visible")
        precondition(shelf.conversionProgress[b.id] == nil)
        shelf.finishConverting([a, c])
        precondition(shelf.convertingItemIDs.isEmpty && shelf.conversionProgress.isEmpty)
        shelf.finishConverting([a])
        shelf.beginConverting([a])
        shelf.finishConverting([a])
        precondition(!shelf.isConverting(a), "Finishing an inactive item must not create a negative count")
        shelf.beginConverting([b])
        shelf.setConversionProgress("Retry Download", for: b)
        shelf.finishConverting([b], preservingProgressForFailures: true)
        precondition(!shelf.isConverting(b) && shelf.conversionProgress[b.id] == "Retry Download")
        shelf.beginConverting([b])
        shelf.finishConverting([b])
        precondition(shelf.conversionProgress[b.id] == nil)
        print("Overlapping conversion checks passed")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = pathlib.Path(directory)
            (folder / "Harness.swift").write_text(fixture)
            executable = folder / "conversion-activity"
            compiled = subprocess.run(
                ["swiftc", "-parse-as-library", str(folder / "Harness.swift"), "-o", str(executable)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(executable)], timeout=20, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Overlapping conversion checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
