import Foundation
import Darwin
import Security

@objc(LonghaulCompanionProtocol)
protocol LonghaulCompanionProtocol {
    func exchange(_ data: Data, with reply: @escaping (Data) -> Void)
}

/// Fixed, local-only relay. The sandboxed app cannot choose a service, peer,
/// executable, or signing requirement through this interface.
enum NodebayLonghaulRelay {
    static let requirement = "anchor apple generic and identifier \"space.exlumina.longhaul.companion\" and certificate leaf[subject.OU] = \"HZWY8HT54D\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    static let unavailable = Data("{\"version\":1,\"serverInstance\":\"unavailable\",\"state\":\"Needs attention\",\"message\":\"Open Longhaul to set up its local connection. Compatible signed apps are required.\"}".utf8)

    static func trusted(_ connection: NSXPCConnection?) -> Bool {
        guard let connection, connection.effectiveUserIdentifier == geteuid() else { return false }
        var code: SecCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"theboringteam.boringnotch\" and certificate leaf[subject.OU] = \"HZWY8HT54D\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: connection.processIdentifier] as CFDictionary, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    static func validControl(_ data: Data) -> Bool {
        guard data.count <= 65_536,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["version"] as? Int == 1,
              let id = value["requestID"] as? String, UUID(uuidString: id) != nil,
              let op = value["op"] as? String,
              ["hello", "status", "connect", "disconnect", "pause", "resume", "keepAwake", "ackAlert"].contains(op),
              Set(value.keys).isSubset(of: ["version", "requestID", "op", "serverInstance", "minutes", "alertID", "capabilities"]),
              op == "hello" || ((value["serverInstance"] as? String).map { !$0.isEmpty && $0.utf8.count <= 180 } ?? false),
              op != "keepAwake" || [30, 60, 240].contains(value["minutes"] as? Int ?? 0),
              op != "ackAlert" || ((value["alertID"] as? String).map { !$0.isEmpty && $0.utf8.count <= 180 } ?? false) else { return false }
        if let rawCapabilities = value["capabilities"] {
            guard ["hello", "status"].contains(op),
                  let capabilities = rawCapabilities as? [String], capabilities.count <= 16,
                  capabilities.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 80 }) else { return false }
        }
        return true
    }

    static func exchange(_ data: Data, reply: @escaping (Data) -> Void) {
        guard data.count <= 65_536 else { reply(unavailable); return }
        let connection = NSXPCConnection(machServiceName: "space.exlumina.longhaul.companion", options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: LonghaulCompanionProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        let gate = ReplyGate(connection: connection, reply: reply)
        connection.invalidationHandler = { gate.finish(unavailable) }
        connection.interruptionHandler = { gate.finish(unavailable) }
        connection.resume()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in gate.finish(unavailable) }) as? LonghaulCompanionProtocol else {
            gate.finish(unavailable); return
        }
        proxy.exchange(data) { response in
            guard connection.effectiveUserIdentifier == geteuid(), response.count <= 65_536 else { gate.finish(unavailable); return }
            gate.finish(response)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { gate.finish(unavailable) }
    }

    private final class ReplyGate: @unchecked Sendable {
        let connection: NSXPCConnection
        let lock = NSLock()
        var reply: ((Data) -> Void)?
        init(connection: NSXPCConnection, reply: @escaping (Data) -> Void) { self.connection = connection; self.reply = reply }
        func finish(_ data: Data) {
            let callback = lock.withLock { let value = reply; reply = nil; return value }
            guard let callback else { return }
            connection.invalidationHandler = nil; connection.interruptionHandler = nil
            connection.invalidate()
            callback(data)
        }
    }
}

enum LonghaulWorkerPolicy {
    /// Only real output-producing work is eligible. Probes and metadata
    /// inspection are deliberately excluded, even when their engine is present.
    static func title(engine: String, arguments: [String]) -> String? {
        switch engine {
        case "markitdown": return arguments.first == "--input" ? "Converting a document" : nil
        case "imageoptim": return arguments.count == 1 && arguments[0].hasPrefix("/") ? "Optimizing an image copy" : nil
        case "ffmpeg": return arguments.contains("-i") && !arguments.contains("-version") ? "Processing media" : nil
        case "yt-dlp":
            guard !arguments.contains("--version"), !arguments.contains("--dump-single-json"),
                  !arguments.contains("--dump-json"), !arguments.contains("--skip-download"),
                  !arguments.contains("--simulate"), !arguments.contains("--flat-playlist") else { return nil }
            return arguments.contains(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }) ? "Downloading media" : nil
        case "stl-repair": return ["safe", "thorough"].contains(arguments.first ?? "") ? "Repairing a model copy" : nil
        default: return nil
        }
    }
}

/// The actual helper worker owns the lease, independently of Nodebay's UI polls.
/// No operation here cancels Longhaul jobs or changes its protection policy.
final class LonghaulWorkerJobs: @unchecked Sendable {
    static let shared = LonghaulWorkerJobs()
    private struct Job {
        var event: [String: Any]
        var finished: Date?
        var cancelled = false
    }
    private let queue = DispatchQueue(label: "Nodebay.longhaul.jobs", qos: .utility)
    private var jobs: [String: Job] = [:]
    private var finishedBeforeStart: [String] = []
    private var timer: DispatchSourceTimer?
    private var publishing = false

    private init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.publish() }
        timer.resume(); self.timer = timer
    }

    func started(id: String, title: String, pid: pid_t) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let birth: UInt64? = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
            ? info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec : nil
        queue.async {
            guard !self.finishedBeforeStart.contains(id), self.jobs.count < 256 else { return }
            var event: [String: Any] = ["version": 1, "id": id, "source": "Nodebay", "title": title,
                "phase": "running", "sequence": 1, "session": UUID().uuidString,
                "pid": pid, "checkpointCapable": false]
            if let birth { event["processBirth"] = birth }
            self.jobs[id] = Job(event: event)
            self.publish()
        }
    }

    func progress(id: String, fraction: Double) {
        guard fraction.isFinite, (0...1).contains(fraction) else { return }
        queue.async {
            guard self.jobs[id]?.finished == nil else { return }
            self.jobs[id]?.event["progress"] = fraction
        }
    }

    func cancelled(id: String) { queue.async { self.jobs[id]?.cancelled = true } }

    func finished(id: String, code: Int32) {
        queue.async {
            guard var job = self.jobs[id] else {
                self.finishedBeforeStart.append(id)
                self.finishedBeforeStart = Array(self.finishedBeforeStart.suffix(256))
                return
            }
            guard job.finished == nil else { return }
            job.event["phase"] = code == 0 ? "completed" : job.cancelled ? "cancelled" : "failed"
            job.finished = Date()
            self.jobs[id] = job
            self.publish()
        }
    }

    private func publish() {
        jobs = jobs.filter { $0.value.finished.map { Date().timeIntervalSince($0) < 120 } ?? true }
        guard !jobs.isEmpty, !publishing else { return }
        publishing = true
        let hello: [String: Any] = ["version": 1, "requestID": UUID().uuidString, "op": "hello"]
        guard let data = try? JSONSerialization.data(withJSONObject: hello) else { publishing = false; return }
        NodebayLonghaulRelay.exchange(data) { response in
            self.queue.async {
                guard let value = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                      value["version"] as? Int == 1, value["state"] as? String == "Connected",
                      let instance = value["serverInstance"] as? String, instance.utf8.count <= 180 else { self.publishing = false; return }
                self.sendNext(Array(self.jobs.keys), instance: instance)
            }
        }
    }

    private func sendNext(_ ids: [String], instance: String) {
        guard let id = ids.first else { publishing = false; return }
        guard var job = jobs[id] else { sendNext(Array(ids.dropFirst()), instance: instance); return }
        job.event["sequence"] = (job.event["sequence"] as? Int ?? 0) + 1
        jobs[id] = job
        let request: [String: Any] = ["version": 1, "requestID": UUID().uuidString, "op": "job", "serverInstance": instance, "job": job.event]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { publishing = false; return }
        NodebayLonghaulRelay.exchange(data) { response in
            self.queue.async {
                guard let value = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                      value["state"] as? String == "Connected", value["serverInstance"] as? String == instance else { self.publishing = false; return }
                self.sendNext(Array(ids.dropFirst()), instance: instance)
            }
        }
    }
}
