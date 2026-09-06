import Foundation

enum LonghaulConnectionState: String, Codable {
    case notInstalled = "Not installed"
    case available = "Available"
    case connected = "Connected"
    case needsAttention = "Needs attention"
}

enum LonghaulControlSurface: String {
    case nodebay, menuBar
}

struct LonghaulCompanionRequest: Codable {
    var version = 1
    var requestID = UUID().uuidString
    var op: String
    var serverInstance: String?
    var minutes: Int?
    var alertID: String?
    var capabilities: [String]?
}

struct LonghaulCompanionAlert: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
}

struct LonghaulCompanionSnapshot: Codable, Equatable {
    struct Job: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let phase: String
        let progress: Double?
    }
    let instanceID: String
    let revision: Int
    let mode: String
    let reason: String
    let protecting: Bool
    let enabled: Bool
    let jobCount: Int
    let jobs: [Job]
    let batteryStage: String
    let batteryPercent: Double?
    let checkpointSummary: String?
    let alerts: [LonghaulCompanionAlert]
    var controlSurface: String?

    var resolvedControlSurface: LonghaulControlSurface {
        controlSurface.flatMap(LonghaulControlSurface.init(rawValue:)) ?? .nodebay
    }

    var isValid: Bool {
        (controlSurface == nil || LonghaulControlSurface(rawValue: controlSurface!) != nil) &&
        !instanceID.isEmpty && instanceID.utf8.count <= 180 && revision >= 0 &&
        (0...10_000).contains(jobCount) && jobs.count <= 100 && alerts.count <= 32 &&
        mode.utf8.count <= 80 && reason.utf8.count <= 1_024 &&
        ["normal", "warning", "prepare", "critical"].contains(batteryStage) &&
        (batteryPercent == nil || (batteryPercent!.isFinite && (0...100).contains(batteryPercent!))) &&
        (checkpointSummary?.utf8.count ?? 0) <= 2_048 &&
        jobs.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 300 && $0.title.utf8.count <= 240 &&
            $0.phase.utf8.count <= 80 && ($0.progress == nil || ($0.progress!.isFinite && (0...1).contains($0.progress!))) } &&
        alerts.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 180 && $0.title.utf8.count <= 240 && $0.body.utf8.count <= 2_048 }
    }
}

struct LonghaulCompanionResponse: Codable {
    let version: Int
    let serverInstance: String
    let state: LonghaulConnectionState
    let message: String?
    let snapshot: LonghaulCompanionSnapshot?

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw LonghaulCompanionError.invalidResponse }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, !value.serverInstance.isEmpty, value.serverInstance.utf8.count <= 180,
              (value.message?.utf8.count ?? 0) <= 2_048,
              value.state != .notInstalled,
              value.snapshot == nil || (value.state == .connected && value.snapshot!.isValid && value.snapshot!.instanceID == value.serverInstance),
              value.state != .connected || value.snapshot != nil else { throw LonghaulCompanionError.invalidResponse }
        return value
    }
}

enum LonghaulCompanionError: LocalizedError {
    case unavailable, invalidResponse, timeout
    var errorDescription: String? {
        switch self {
        case .unavailable: "Open Longhaul to set up its local connection. Both apps must have compatible Developer ID signatures."
        case .invalidResponse: "Longhaul returned an incompatible or invalid response. Update both apps and try again."
        case .timeout: "Longhaul did not respond. Its independent protection has not been changed."
        }
    }
}

/// A server restart resets the revision epoch. Older responses from the same
/// instance never replace fresher UI, including when a control overlaps a poll.
struct LonghaulSnapshotCursor {
    private(set) var instance: String?
    private(set) var revision = -1
    private var controlSurface: LonghaulControlSurface?
    mutating func accept(_ snapshot: LonghaulCompanionSnapshot) -> Bool {
        guard snapshot.isValid else { return false }
        if instance == snapshot.instanceID {
            guard snapshot.revision >= revision else { return false }
            if snapshot.revision == revision && controlSurface != snapshot.resolvedControlSurface { return false }
        }
        instance = snapshot.instanceID; revision = snapshot.revision
        controlSurface = snapshot.resolvedControlSurface
        return true
    }
    mutating func reset() { instance = nil; revision = -1; controlSurface = nil }
}

struct LonghaulAlertLedger {
    private(set) var delivered: [String]
    init(delivered: [String] = []) { self.delivered = Array(delivered.suffix(256)) }
    func contains(_ id: String) -> Bool { delivered.contains(id) }
    mutating func record(_ id: String) {
        guard !contains(id) else { return }
        delivered.append(id)
        delivered = Array(delivered.suffix(256))
    }
}
