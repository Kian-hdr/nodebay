import Foundation

@main
struct LonghaulCompanionHarness {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        func encoded(_ patch: [String: Any] = [:]) throws -> Data {
            var response: [String: Any] = ["version": 1, "serverInstance": "server-1", "state": "Connected", "snapshot": snapshot()]
            patch.forEach { response[$0.key] = $0.value }
            return try JSONSerialization.data(withJSONObject: response)
        }
        func snapshot(_ patch: [String: Any] = [:]) -> [String: Any] {
            var value: [String: Any] = ["instanceID": "server-1", "revision": 2, "mode": "protecting", "reason": "Two jobs are protected", "protecting": true, "enabled": true, "jobCount": 2,
                "jobs": [["id": "a", "title": "Render", "phase": "running", "progress": 0.5], ["id": "b", "title": "Download", "phase": "waiting"]], "batteryStage": "normal", "batteryPercent": 65, "alerts": [["id": "alert-1", "title": "Saved", "body": "Recovery is available"]]]
            patch.forEach { value[$0.key] = $0.value }; return value
        }
        func rejects(_ data: Data) -> Bool { (try? LonghaulCompanionResponse.decode(data)) == nil }
        let valid = try LonghaulCompanionResponse.decode(encoded())
        check(valid.snapshot?.jobCount == 2, "Concurrent jobs survive decoding")
        check(valid.snapshot?.jobs.last?.progress == nil, "Unknown progress remains unknown")
        check(valid.snapshot?.resolvedControlSurface == .nodebay, "Missing legacy route defaults to Nodebay")
        for route in ["nodebay", "menuBar"] {
            let routed = try LonghaulCompanionResponse.decode(encoded(["snapshot": snapshot(["controlSurface": route])]))
            check(routed.snapshot?.controlSurface == route, "Recognized control route decodes")
        }
        let nullRoute = try LonghaulCompanionResponse.decode(encoded(["snapshot": snapshot(["controlSurface": NSNull()])]))
        check(nullRoute.snapshot?.resolvedControlSurface == .nodebay, "Null legacy route defaults to Nodebay")
        for route in ["", "menubar", "elsewhere", String(repeating: "x", count: 1_000)] {
            check(rejects(try encoded(["snapshot": snapshot(["controlSurface": route])])), "Unknown route rejected")
        }
        check(rejects(try encoded(["snapshot": snapshot(["controlSurface": 1])])), "Non-string route rejected")
        check(rejects(try encoded(["version": 2])), "Incompatible version rejected")
        check(rejects(Data(repeating: 32, count: 65_537)), "Oversized reply rejected")
        check(rejects(Data("not JSON".utf8)), "Malformed reply rejected")
        check(rejects(try encoded(["snapshot": NSNull()])), "Connected requires current snapshot")
        check(rejects(try encoded(["state": "Available"])), "Unpaired reply may not reveal status")
        check(rejects(try encoded(["snapshot": snapshot(["instanceID": "other"])])), "Epoch mismatch rejected")
        check(rejects(try encoded(["snapshot": snapshot(["batteryPercent": 101])])), "Out of bounds battery rejected")
        check(rejects(try encoded(["snapshot": snapshot(["jobs": [["id": "a", "title": "Bad progress", "phase": "running", "progress": -0.1]]])])), "Out of bounds progress rejected")
        check(rejects(try encoded(["snapshot": snapshot(["alerts": Array(repeating: ["id": "x", "title": "x", "body": "x"], count: 33)])])), "Bounded alerts")
        let available = try LonghaulCompanionResponse.decode(encoded(["state": "Available", "snapshot": NSNull()]))
        check(available.state == .available, "Installed is not connected")
        var cursor = LonghaulSnapshotCursor()
        check(cursor.accept(valid.snapshot!), "First revision accepted")
        let older = try LonghaulCompanionResponse.decode(encoded(["snapshot": snapshot(["revision": 1])]))
        check(!cursor.accept(older.snapshot!), "Stale revision rejected")
        let conflictingRoute = try LonghaulCompanionResponse.decode(encoded(["snapshot": snapshot(["controlSurface": "menuBar"])]))
        check(!cursor.accept(conflictingRoute.snapshot!), "Same revision cannot change control route")
        check(cursor.accept(valid.snapshot!), "Identical same-revision snapshot remains acceptable")
        let restart = try LonghaulCompanionResponse.decode(encoded(["serverInstance": "server-2", "snapshot": snapshot(["instanceID": "server-2", "revision": 0])]))
        check(cursor.accept(restart.snapshot!), "Restart resets revision epoch")
        var alerts = LonghaulAlertLedger()
        alerts.record("a"); alerts.record("a")
        check(alerts.delivered.count == 1, "Duplicate delivery suppressed")
        alerts = LonghaulAlertLedger(delivered: alerts.delivered)
        check(alerts.contains("a"), "Restart preserves alert suppression")
        for i in 0..<300 { alerts.record("id-\(i)") }
        check(alerts.delivered.count == 256, "Alert ledger remains bounded")
        for (engine, args) in [("ffmpeg", ["-version"]), ("yt-dlp", ["--version"]), ("yt-dlp", ["--dump-single-json", "https://example.invalid/test"]), ("markitdown", ["--nodebay-version"]), ("stl-repair", ["inspect", "/job"]), ("homebrew", ["install", "ffmpeg"])] {
            check(LonghaulWorkerPolicy.title(engine: engine, arguments: args) == nil, "Probe never becomes a job")
        }
        check(LonghaulWorkerPolicy.title(engine: "ffmpeg", arguments: ["-i", "/input", "/output"]) != nil, "Actual media output is a job")
        check(LonghaulWorkerPolicy.title(engine: "yt-dlp", arguments: ["--ignore-config", "https://example.invalid/test"]) != nil, "Actual download is a job")
        check(LonghaulWorkerPolicy.title(engine: "stl-repair", arguments: ["safe", "/job"]) != nil, "Actual repair is a job")
        func request(_ op: String, _ patch: [String: Any] = [:]) throws -> Data {
            var value: [String: Any] = ["version": 1, "requestID": UUID().uuidString, "op": op, "serverInstance": "server-1"]
            patch.forEach { value[$0.key] = $0.value }
            return try JSONSerialization.data(withJSONObject: value)
        }
        check(NodebayLonghaulRelay.validControl(try request("hello")), "Hello allowed")
        for op in ["hello", "status"] {
            check(NodebayLonghaulRelay.validControl(try request(op, ["capabilities": ["control-surface-v1"]])), "Read-only capability negotiation forwards")
        }
        for op in ["connect", "disconnect", "pause", "resume", "keepAwake", "ackAlert"] {
            check(!NodebayLonghaulRelay.validControl(try request(op, ["capabilities": ["control-surface-v1"], "minutes": 30, "alertID": "fixture"])), "Mutations cannot carry capabilities")
        }
        for capabilities: Any in ["control-surface-v1", [1], [""], [String(repeating: "x", count: 81)], Array(repeating: "x", count: 17), NSNull()] {
            check(!NodebayLonghaulRelay.validControl(try request("hello", ["capabilities": capabilities])), "Malformed or unbounded capability list rejected")
        }
        check(NodebayLonghaulRelay.validControl(try request("keepAwake", ["minutes": 30])), "Approved duration allowed")
        check(!NodebayLonghaulRelay.validControl(try request("keepAwake", ["minutes": 999])), "Unbounded keep awake refused")
        check(!NodebayLonghaulRelay.validControl(try request("run", ["command": "unexpected"])), "Arbitrary command refused")
        check(!NodebayLonghaulRelay.validControl(try request("job", ["job": [:]])), "App cannot forge helper worker jobs")
        check(!NodebayLonghaulRelay.validControl(try request("pause", ["serverInstance": NSNull()])), "Mutation needs current instance")
        check(!NodebayLonghaulRelay.validControl(try request("pause", ["url": "https://example.invalid"])), "Unknown field refused")
        check(!NodebayLonghaulRelay.validControl(Data(repeating: 32, count: 65_537)), "Oversized request refused")
        print("Longhaul companion: \(checks) checks passed")
    }
}
