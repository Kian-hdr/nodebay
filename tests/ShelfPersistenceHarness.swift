import Foundation

// Exercise the production persistence service with a Codable fixture whose
// encoder can be paused deterministically while a newer flush is requested.
struct ShelfItem: Codable, Equatable, Sendable {
    let value: String
    enum CodingKeys: String, CodingKey { case value }
    enum FixtureError: Error { case rejected }

    init(_ value: String) { self.value = value }

    func encode(to encoder: Encoder) throws {
        EncodingProbe.shared.begin(value)
        defer { EncodingProbe.shared.end() }
        if value == "reject-encoding" { throw FixtureError.rejected }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

final class EncodingProbe: @unchecked Sendable {
    static let shared = EncodingProbe()
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var active = 0
    private var peak = 0
    private var recorded: [String] = []

    func begin(_ value: String) {
        lock.lock()
        active += 1
        peak = max(peak, active)
        recorded.append(value)
        lock.unlock()
        if value == "blocked-old" {
            started.signal()
            guard release.wait(timeout: .now() + 10) == .success else {
                fatalError("Timed out releasing older encoder")
            }
        }
    }

    func end() { lock.lock(); active -= 1; lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    var maximumConcurrentEncoders: Int { lock.lock(); defer { lock.unlock() }; return peak }
}

@main struct ShelfPersistenceHarness {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let file = directory.appendingPathComponent("items.json")
        let service = ShelfPersistenceService(fileURL: file)
        switch CommandLine.arguments[1] {
        case "cancelled-write":
            let old = Task { await service.saveAsync([ShelfItem("blocked-old")]) }
            let started = await Task.detached {
                EncodingProbe.shared.started.wait(timeout: .now() + 5) == .success
            }.value
            require(started, "Older async save must begin before the flush")
            old.cancel()
            // The release is independent of MainActor: a synchronous flush may
            // block it, but must never require MainActor to drain an IO write.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                EncodingProbe.shared.release.signal()
            }
            service.save([ShelfItem("latest-flush")])
            await old.value
            require(service.load() == [ShelfItem("latest-flush")],
                    "A cancelled older async save overwrote the newest synchronous flush")
            require(EncodingProbe.shared.maximumConcurrentEncoders == 1,
                    "The shared JSONEncoder must never run concurrently")
        case "ordered-writes":
            let old = Task { await service.saveAsync([ShelfItem("blocked-old")]) }
            let started = await Task.detached {
                EncodingProbe.shared.started.wait(timeout: .now() + 5) == .success
            }.value
            require(started, "Older async save must begin before ordered admissions")
            var admissions: [String] = []
            var writes: [Task<Void, Never>] = []
            for index in 0..<200 {
                writes.append(Task { @MainActor in
                    let value = "pending-\(index)"
                    admissions.append(value)
                    await service.saveAsync([ShelfItem(value)])
                })
            }
            while admissions.count < writes.count { await Task.yield() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                EncodingProbe.shared.release.signal()
            }
            service.save([ShelfItem("latest-flush")])
            await old.value
            for write in writes { await write.value }
            require(EncodingProbe.shared.values == ["blocked-old"] + admissions + ["latest-flush"],
                    "Persistence must encode and write in MainActor admission order")
            require(service.load() == [ShelfItem("latest-flush")],
                    "Pending background writes must finish before synchronous flush returns")
            require(EncodingProbe.shared.maximumConcurrentEncoders == 1,
                    "Pending writes raced on the shared encoder")
        case "round-trip":
            require(service.load().isEmpty, "A missing shelf file should load as empty")
            let items = [ShelfItem("saved text"), ShelfItem("第二条 🗂️")]
            await service.saveAsync(items)
            require(service.load() == items, "Async save must complete its atomic write before returning")
            let original = try Data(contentsOf: file)
            service.save([ShelfItem("reject-encoding")])
            let afterFailure = try Data(contentsOf: file)
            require(afterFailure == original, "Failed encoding must preserve the existing shelf")
            let corrupt = Data("[{\"value\":\"retained\"},{\"wrongKey\":1}]".utf8)
            try corrupt.write(to: file, options: .atomic)
            require(service.load() == [ShelfItem("retained")], "Partial recovery must retain valid shelf items")
            service.save([])
            require(service.load().isEmpty, "An intentional empty shelf must persist")
        default:
            fatalError("Unknown harness case")
        }
        print("Shelf persistence \(CommandLine.arguments[1]) checks passed")
    }
}
