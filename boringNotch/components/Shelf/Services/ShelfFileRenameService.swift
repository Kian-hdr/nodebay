import Foundation

enum ShelfFileRenameError: LocalizedError, Equatable {
    case invalidName
    case destinationExists
    case sourceMissing
    case fileOperationFailed

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a valid file name without slashes, colons, or control characters."
        case .destinationExists:
            return "A file with that name already exists in this folder."
        case .sourceMissing:
            return "The original file is no longer available."
        case .fileOperationFailed:
            return "The file could not be renamed. Check its permissions and try again."
        }
    }
}

/// Performs same-folder, collision-safe file renames. Nodebay never uses this
/// operation to change a file's type or replace another file.
enum ShelfFileRenameService {
    static func destination(for source: URL, requestedStem: String) throws -> URL {
        let stem = requestedStem.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        guard !stem.isEmpty,
              stem != ".",
              stem != "..",
              stem.rangeOfCharacter(from: forbidden) == nil else {
            throw ShelfFileRenameError.invalidName
        }

        let fileExtension = source.pathExtension
        let filename = fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
        return source.deletingLastPathComponent().appendingPathComponent(filename, isDirectory: false)
    }

    static func rename(_ source: URL, requestedStem: String) async throws -> URL {
        let destination = try destination(for: source, requestedStem: requestedStem)
        if destination.standardizedFileURL == source.standardizedFileURL { return source }

        return try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            guard manager.fileExists(atPath: source.path) else {
                throw ShelfFileRenameError.sourceMissing
            }
            guard !manager.fileExists(atPath: destination.path) else {
                throw ShelfFileRenameError.destinationExists
            }
            do {
                try manager.moveItem(at: source, to: destination)
                return destination
            } catch let error as ShelfFileRenameError {
                throw error
            } catch {
                throw ShelfFileRenameError.fileOperationFailed
            }
        }.value
    }
}
