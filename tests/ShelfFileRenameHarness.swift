import Foundation

@main
struct ShelfFileRenameHarness {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nodebay-rename-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("Quick Note 2026-09-06 12-00.md")
        let contents = Data("# Persistent note\n\nBody\n".utf8)
        try contents.write(to: original)

        let expected = try ShelfFileRenameService.destination(for: original, requestedStem: "Project Notes")
        precondition(expected.lastPathComponent == "Project Notes.md")
        let renamed = try await ShelfFileRenameService.rename(original, requestedStem: "Project Notes")
        precondition(renamed == expected)
        precondition(!FileManager.default.fileExists(atPath: original.path))
        let renamedContents = try Data(contentsOf: renamed)
        precondition(renamedContents == contents)

        let collision = root.appendingPathComponent("Existing.md")
        try Data("existing".utf8).write(to: collision)
        do {
            _ = try await ShelfFileRenameService.rename(renamed, requestedStem: "Existing")
            preconditionFailure("collision must fail")
        } catch ShelfFileRenameError.destinationExists {}
        let collisionContents = try Data(contentsOf: collision)
        let preservedContents = try Data(contentsOf: renamed)
        precondition(collisionContents == Data("existing".utf8))
        precondition(preservedContents == contents)

        for invalid in ["", "   ", ".", "..", "folder/name", "bad:name", "bad\u{0}name"] {
            do {
                _ = try ShelfFileRenameService.destination(for: renamed, requestedStem: invalid)
                preconditionFailure("invalid name accepted")
            } catch ShelfFileRenameError.invalidName {}
        }

        let unchanged = try await ShelfFileRenameService.rename(renamed, requestedStem: "Project Notes")
        precondition(unchanged == renamed)
        let unchangedContents = try Data(contentsOf: unchanged)
        precondition(unchangedContents == contents)
        print("shelf rename behavioral fixtures passed")
    }
}
