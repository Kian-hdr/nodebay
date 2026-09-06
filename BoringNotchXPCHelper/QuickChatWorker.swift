import Foundation
import Security

/// Dedicated typed entry point, not an extension of runApprovedProcess. Caller
/// supplies only bounded text and an ID, never a program, path or CLI option.
final class QuickChatWorker: @unchecked Sendable {
    static let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"
    // Exact locally exercised builds, never a permissive version range.
    // This compatibility list does not certify the broader release isolation gate.
    static let supportedVersions: Set<String> = ["0.152.1", "0.153.0-alpha.5", "0.153.4"]

    private static func supportedVersion(_ output: String) -> String? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return supportedVersions.first { line == "codex-cli \($0)" }
    }
    private let lock = NSLock()
    private var running: (String, Process)?
    private var cancelled = Set<String>()
    private let queue = DispatchQueue(label: "Nodebay.quick-chat", qos: .userInitiated)

    private static let disabled = [
        "hooks", "plugins", "remote_plugin", "apps", "computer_use", "browser_use",
        "browser_use_external", "browser_use_full_cdp_access", "in_app_browser",
        "multi_agent", "memories", "shell_snapshot", "shell_tool", "unified_exec",
        "view_image", "image_generation", "workspace_dependencies", "skill_search",
        "skill_mcp_dependency_install", "goals", "sleep_tool", "code_mode_host"
    ]

    func cancel(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        if cancelled.count > 128 { cancelled.removeAll() }
        cancelled.insert(id)
        if let (activeID, process) = running, activeID == id, process.isRunning { process.terminate() }
    }

    func cancelAll() {
        lock.lock(); defer { lock.unlock() }
        if let (id, process) = running {
            cancelled.insert(id)
            if process.isRunning { process.terminate() }
        }
    }

    private func trustedExecutable() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: Self.executable) else { return false }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: Self.executable) as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple generic and identifier codex and certificate leaf[subject.OU] = \"2DC432GLL2\"" as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    func status(_ reply: @escaping (String, String) -> Void) {
        queue.async {
            guard self.trustedExecutable() else { reply("missing", ""); return }
            let version = self.run(id: UUID().uuidString, arguments: ["--version"], input: nil,
                                   directory: URL(fileURLWithPath: "/private/tmp"), timeout: 10)
            guard version.code == 0, let detectedVersion = Self.supportedVersion(version.out) else {
                reply("incompatible", "Unverified CLI version"); return
            }
            let auth = self.run(id: UUID().uuidString, arguments: ["login", "status"], input: nil,
                                directory: URL(fileURLWithPath: "/private/tmp"), timeout: 10)
            // Never return the provider's raw account/status output to the app.
            let hasChatGPT = (auth.out + auth.err).contains("Logged in using ChatGPT")
            reply(auth.code == 0 && hasChatGPT ? "ready" : "signedOut", detectedVersion)
        }
    }

    static func reasoningArguments(thinkDeeper: Bool) -> [String] {
        thinkDeeper ? ["-c", "model_reasoning_effort=\"high\""] : []
    }

    func answer(_ id: String, context: String, thinkDeeper: Bool, reply: @escaping (String, String) -> Void) {
        guard UUID(uuidString: id) != nil, !context.isEmpty, context.utf8.count <= 65_536,
              !context.contains("\0") else { reply("failed", ""); return }
        queue.async {
            guard self.trustedExecutable() else { reply("incompatible", ""); return }
            let version = self.run(id: id, arguments: ["--version"], input: nil,
                directory: URL(fileURLWithPath: "/private/tmp"), timeout: 10)
            guard version.code == 0, Self.supportedVersion(version.out) != nil else {
                reply("incompatible", ""); return
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NodebayChat-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]) }
            catch { reply("failed", ""); return }
            let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let instructions = app.appendingPathComponent("Contents/Resources/QuickChatInstructions-v1.md")
            guard FileManager.default.fileExists(atPath: instructions.path) else { reply("incompatible", ""); return }
            var arguments = ["exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--json",
                             "--skip-git-repo-check", "--strict-config"]
            for name in Self.disabled { arguments += ["--disable", name] }
            arguments += ["--enable", "skip_host_skill_discovery"]
            for setting in [
                "default_permissions=\"nodebay_chat\"",
                "permissions.nodebay_chat.filesystem={\"/\"=\"deny\"}",
                "permissions.nodebay_chat.network.enabled=false", "approval_policy=\"never\"",
                "web_search=\"disabled\"", "analytics.enabled=false", "history.persistence=\"none\"",
                "project_doc_max_bytes=0", "notify=[]",
                "model_instructions_file=\"\(instructions.path)\"",
                // Keep the provider's own initialized database. Relocating it
                // per request makes the CLI rebuild its state before each turn.
                // --ephemeral and history.persistence=none still apply.
                "log_dir=\"\(directory.path)/logs\""
            ] { arguments += ["-c", setting] }
            arguments += Self.reasoningArguments(thinkDeeper: thinkDeeper) + ["-"]
            let result = self.run(id: id, arguments: arguments, input: context, directory: directory, timeout: 90)
            guard result.code == 0 else { reply(result.code == -2 ? "timeout" : "failed", ""); return }
            let parsed = QuickChatReplyParser.parse(result.out)
            reply(parsed.state, parsed.text)
        }
    }

    private func run(id: String, arguments: [String], input: String?, directory: URL, timeout: TimeInterval)
        -> (code: Int32, out: String, err: String) {
        let process = Process(), stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        let output = ChatCapture(), errors = ChatCapture()
        // OS-level backstop: the CLI cannot launch shells, plugin executables,
        // browsers or arbitrary child programs, even if configuration regresses.
        let profile = "(version 1) (allow default) (deny process-exec (require-not (literal \"\(Self.executable)\")))"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", profile, Self.executable] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = stdout; process.standardError = stderr
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        // Preserve the provider's existing home, without reading/copying auth.
        let inherited = ProcessInfo.processInfo.environment
        process.environment = inherited.filter { ["HOME", "CODEX_HOME", "USER", "LOGNAME", "TMPDIR", "LANG"].contains($0.key) }
            .merging(["PATH": "/usr/bin:/bin"]) { _, new in new }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            if !output.append(handle.availableData), process.isRunning { process.terminate() }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if !errors.append(handle.availableData), process.isRunning { process.terminate() }
        }
        lock.lock()
        guard !cancelled.contains(id) else { lock.unlock(); return (-3, "", "") }
        running = (id, process)
        do { try process.run() } catch { running = nil; lock.unlock(); return (-1, "", "") }
        lock.unlock()
        if let input {
            DispatchQueue.global(qos: .userInitiated).async {
                try? stdin.fileHandleForWriting.write(contentsOf: Data((input + "\n").utf8))
                try? stdin.fileHandleForWriting.close()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            lock.lock(); let stopping = cancelled.contains(id); lock.unlock()
            if stopping { process.terminate(); break }
            if Date() >= deadline { timedOut = true; process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        if process.isRunning {
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        _ = output.append(stdout.fileHandleForReading.readDataToEndOfFile())
        _ = errors.append(stderr.fileHandleForReading.readDataToEndOfFile())
        lock.lock(); running = nil; let wasCancelled = cancelled.contains(id); lock.unlock()
        return (wasCancelled ? -3 : timedOut ? -2 : process.terminationStatus, output.text, errors.text)
    }
}

final class ChatCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflowed = false
    func append(_ value: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !overflowed, data.count + value.count <= 1_048_576 else { overflowed = true; return false }
        data.append(value); return true
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return overflowed ? "" : String(decoding: data, as: UTF8.self) }
}

/// Validates complete CLI messages. Deliberately NOT a token streaming adapter:
/// App Server is gated off until its inherited tools/config can be isolated.
enum QuickChatReplyParser {
    static func parse(_ output: String) -> (state: String, text: String) {
        guard output.utf8.count <= 1_048_576 else { return ("failed", "") }
        var started = false, completed = false
        var messages: [String: String] = [:], text = ""
        for line in output.split(separator: "\n") {
            guard !completed, let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { return ("failed", "") }
            switch type {
            case "thread.started": break
            case "turn.started":
                guard !started else { return ("failed", "") }; started = true
            case "turn.completed":
                guard started else { return ("failed", "") }; completed = true
            case "turn.failed", "error": return ("failed", "")
            case "item.started", "item.updated", "item.completed":
                guard let item = event["item"] as? [String: Any], let kind = item["type"] as? String else { return ("failed", "") }
                switch kind {
                case "reasoning", "error": break // Private payloads never cross XPC.
                case "agent_message":
                    guard started else { return ("failed", "") }
                    if type == "item.completed" {
                        guard let id = item["id"] as? String, !id.isEmpty,
                              let content = item["text"] as? String else { return ("failed", "") }
                        if let previous = messages[id] {
                            guard previous == content else { return ("failed", "") }
                            continue
                        }
                        guard text.utf8.count + content.utf8.count <= 32_768 else { return ("failed", "") }
                        messages[id] = content; text += content
                    }
                default: return ("unsafe", "")
                }
            default: return ("unsafe", "")
            }
        }
        return completed && !text.isEmpty ? ("completed", text) : ("failed", "")
    }
}
