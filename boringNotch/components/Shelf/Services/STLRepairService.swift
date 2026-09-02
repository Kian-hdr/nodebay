import Foundation
import Darwin

enum STLRepairMode: String, CaseIterable, Codable, Identifiable {
    case safe, thorough, inspect
    var id: Self { self }
    var title: String { switch self { case .safe: "Safe Repair"; case .thorough: "Thorough Repair"; case .inspect: "Inspect Only" } }
}

enum STLRepairError: String, LocalizedError {
    case unsupported = "Choose a local STL model."
    case unavailable = "Install Blender 5.0.1 in Applications to enable local STL repair."
    case failed = "The mesh could not be repaired. It may be malformed, exceed the limits, or need manual repair. The original is unchanged."
    case limit = "STL repair supports files up to 32 MiB and 200,000 triangles."
    case busy = "Another mesh repair is running. Wait or cancel it first."
    case invalidOutput = "The engine did not produce a valid STL within the required bounds. The original is unchanged."
    case confirmation = "Thorough Repair requires confirmation before it can fill boundaries."
    var errorDescription: String? { rawValue }
}

struct STLMeshCounts: Codable, Sendable {
    let triangles, vertices, holes, boundary_edges, non_manifold_edges: Int
    let degenerate_faces, duplicate_faces, normal_errors, winding_edges, components: Int
}

struct STLRepairReport: Codable, Sendable {
    let engine, mode, status: String
    let before, after: STLMeshCounts
    let holes_closed, normals_corrected, removed_duplicates, removed_degenerate: Int
    let remeshed, geometry_changed, scale_changed: Bool
    let warnings: [String]
    let self_intersections: String
    let input_bytes, output_bytes: Int
    let duration: Double
}

struct STLRepairResult: Sendable {
    let outputURL: URL?
    let report: STLRepairReport
}

actor STLRepairService {
    static let shared = STLRepairService()
    static let testedVersion = "5.0.1"
    static let executable = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
    private var running = false
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nodebay")
    }
    nonisolated static func supports(_ url: URL) -> Bool { url.isFileURL && url.pathExtension.lowercased() == "stl" }

    func process(_ source: URL, mode: STLRepairMode, confirmed: Bool = false) async throws -> STLRepairResult {
        guard Self.supports(source) else { throw STLRepairError.unsupported }
        guard mode != .thorough || confirmed else { throw STLRepairError.confirmation }
        guard !running else { throw STLRepairError.busy }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        guard await XPCHelperClient.shared.firstAvailableApprovedExecutable(engine: "stl-repair", candidates: [Self.executable]) != nil else { throw STLRepairError.unavailable }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let bytes = size.fileSize, bytes > 0, bytes <= 32 * 1024 * 1024 else { throw STLRepairError.limit }
        let job = root.appendingPathComponent("STLJobs/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: job) }
        // Only this owned copy reaches Blender, never the user's model.
        try FileManager.default.copyItem(at: source, to: job.appendingPathComponent("input.stl"))
        try Task.checkCancellation()
        let process: ProcessResult
        do {
            process = try await SafeProcessRunner.runApproved(engine: "stl-repair", executable: Self.executable,
                arguments: [mode.rawValue, job.path], timeout: .seconds(160), maximumLogBytes: 4_096)
        } catch {
            try Task.checkCancellation()
            throw STLRepairError.failed
        }
        try Task.checkCancellation()
        guard process.exitCode == 0 else { throw STLRepairError.failed }
        let reportURL = job.appendingPathComponent("report.json")
        guard try reportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 < 32_768 else { throw STLRepairError.invalidOutput }
        let report = try JSONDecoder().decode(STLRepairReport.self, from: Data(contentsOf: reportURL))
        guard report.engine == Self.testedVersion, report.mode == mode.rawValue, !report.scale_changed, !report.remeshed else { throw STLRepairError.invalidOutput }
        if mode == .inspect { return .init(outputURL: nil, report: report) }
        let staged = job.appendingPathComponent("output.stl")
        try Self.validateBinaryOutput(staged)
        try Task.checkCancellation()
        let outputs = root.appendingPathComponent("Repaired Models", isDirectory: true)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Atomic no-overwrite promotion on the same filesystem. The staging
        // directory is removed afterward; the retained hard link remains valid.
        let stem = Self.safeStem(source.deletingPathExtension().lastPathComponent)
        for index in 1...10_000 {
            let suffix = index == 1 ? "" : "-\(index)"
            let output = outputs.appendingPathComponent("\(stem)-repaired\(suffix).stl")
            if link(staged.path, output.path) == 0 { return .init(outputURL: output, report: report) }
            guard errno == EEXIST else { throw STLRepairError.invalidOutput }
        }
        throw STLRepairError.invalidOutput
    }

    nonisolated static func safeStem(_ name: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let value = String(name.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined().prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "." || value == ".." ? "Model" : value
    }

    nonisolated static func validateBinaryOutput(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              let size = values.fileSize, size >= 134, size <= 32 * 1024 * 1024 else { throw STLRepairError.invalidOutput }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        func uint(_ offset: Int) -> UInt32 { data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) } }
        let count = Int(uint(80))
        guard count > 0, count <= 200_000, data.count == 84 + count * 50 else { throw STLRepairError.invalidOutput }
        for triangle in 0..<count {
            let offset = 84 + triangle * 50
            let v = (0..<12).map { Double(Float(bitPattern: uint(offset + $0 * 4))) }
            guard v.allSatisfy(\.isFinite) else { throw STLRepairError.invalidOutput }
            let a = (0..<3).map { v[6+$0]-v[3+$0] }, b = (0..<3).map { v[9+$0]-v[3+$0] }
            let cross = [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
            guard cross.contains(where: { $0 != 0 }) else { throw STLRepairError.invalidOutput }
        }
    }
}
