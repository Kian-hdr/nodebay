import AppKit
import Combine
import Foundation

@main
struct MediaDiscoveryRecoveryHarness {
    @MainActor
    static func waitUntil(_ condition: () -> Bool, seconds: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            precondition(Date() < deadline, "Timed out waiting for media discovery recovery")
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("Fixture.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data().write(to: framework.appendingPathComponent("MediaRemoteAdapter"))
        let script = root.appendingPathComponent("fixture.pl")
        try #"""
        use strict;
        use warnings;
        $| = 1;
        my $folder = $ARGV[0];
        die "full snapshot mode missing" unless $ARGV[1] eq "stream" && $ARGV[2] eq "--no-diff" && $ARGV[3] eq "--allow-missing-title";
        open(my $log, '>>', "$folder/attempts") or die $!;
        print $log "$$\n";
        close($log);
        if (!-f "$folder/started") {
            open(my $marker, '>', "$folder/started") or die $!;
            close($marker);
            exit 7;
        }
        print "{\"diff\":false,\"payload\":{\"bundleIdentifier\":\"fixture.player\",\"title\":\"Recovered track\",\"playing\":true}}\n";
        $SIG{TERM} = sub { exit 0; };
        while (1) { sleep 1; }
        """#.write(to: script, atomically: true, encoding: .utf8)
        let resources = MediaRemoteAdapterResources(scriptURL: script, frameworkURL: framework)
        guard let controller = NowPlayingController(adapterResources: resources) else {
            preconditionFailure("System MediaRemote command entry points unavailable")
        }
        defer { controller.shutdown() }
        try await waitUntil { controller.playbackIssue?.contains("reconnecting") == true }
        try await waitUntil { controller.playbackState.title == "Recovered track" }
        precondition(controller.playbackIssue == nil)
        let attemptsURL = framework.appendingPathComponent("attempts")
        let attempts = try String(contentsOf: attemptsURL, encoding: .utf8).split(separator: "\n")
        precondition(attempts.count == 2, "Failed helper must restart once and recover")
        print("PASS an exited adapter restarts and publishes a fresh full snapshot")

        controller.shutdown()
        let pid = Int32(attempts[1])!
        try await waitUntil { kill(pid, 0) != 0 }
        try await Task.sleep(for: .milliseconds(1200))
        let after = try String(contentsOf: attemptsURL, encoding: .utf8).split(separator: "\n")
        precondition(after.count == 2, "Shutdown must cancel all retry work")
        print("PASS shutdown terminates the owned helper and prevents restarts")

        var transient = NowPlayingController(adapterResources: resources)
        weak var weakController = transient
        try await waitUntil { transient?.playbackState.title == "Recovered track" }
        let transientPID = Int32(try String(contentsOf: attemptsURL, encoding: .utf8).split(separator: "\n").last!)!
        transient = nil
        try await waitUntil { weakController == nil && kill(transientPID, 0) != 0 }
        print("PASS releasing a controller tears down its stream without a retain cycle")

        guard let missing = NowPlayingController(adapterResources: nil) else { preconditionFailure() }
        defer { missing.shutdown() }
        try await waitUntil { missing.playbackIssue?.contains("Reinstall") == true }
        precondition(!missing.playbackState.hasMedia)
        print("PASS missing release resources produce an actionable empty state")

        let denied = NSError(domain: AppleScriptHelper.errorDomain, code: -1743)
        precondition(MediaPlaybackIssue.message(for: denied, applicationName: "Spotify").contains("Automation"))
        precondition(MediaPlaybackIssue.message(for: denied, applicationName: "Spotify").contains("Spotify"))
        precondition(!MediaPlaybackIssue.message(for: NSError(domain: "network", code: -1743), applicationName: "Spotify").contains("Automation"))
        print("PASS only an actual Apple Events denial gives Automation recovery guidance")

        let handler = JSONLinesPipeHandler()
        let pipe = await handler.getPipe()
        var decodedTitles: [String] = []
        let reader = Task {
            await handler.readJSONLines(as: NowPlayingUpdate.self) { update in
                await MainActor.run { decodedTitles.append(update.payload.title ?? "") }
            }
        }
        let json = Data("{\"payload\":{\"title\":\"Hello 🎵 日本語\"}}\n".utf8)
        let split = json.firstIndex(of: 0xF0)! + 1
        try pipe.fileHandleForWriting.write(contentsOf: json[..<split])
        try await Task.sleep(for: .milliseconds(50))
        try pipe.fileHandleForWriting.write(contentsOf: json[split...])
        try pipe.fileHandleForWriting.close()
        await reader.value
        precondition(decodedTitles == ["Hello 🎵 日本語"])
        await handler.close()
        print("PASS a Unicode scalar split across pipe reads preserves metadata")

        let idle = JSONLinesPipeHandler()
        let pending = Task { await idle.readJSONLines(as: NowPlayingUpdate.self) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        await idle.close()
        await pending.value
        print("PASS closing a silent pipe releases its suspended reader")
    }
}
