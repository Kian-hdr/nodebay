import Foundation

@main struct QuickChatWorkerHarness {
    static func main() throws {
        func event(_ type: String, item: [String: String]? = nil) -> String {
            var object: [String: Any] = ["type": type]
            if let item { object["item"] = item }
            return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        func message(_ text: String, id: String = "1") -> String {
            event("item.completed", item: ["id": id, "type": "agent_message", "text": text])
        }
        func parse(_ events: [String]) -> (state: String, text: String) {
            QuickChatReplyParser.parse(events.joined(separator: "\n"))
        }
        let start = event("turn.started"), end = event("turn.completed")
        precondition(parse([start, message("日本語 🦉"), end]).text == "日本語 🦉")
        precondition(parse([start, message("one"), message("two", id: "2"), end]).text == "onetwo")
        precondition(parse([start, message("one"), message("one"), end]).text == "one")
        precondition(parse([start, message("one"), message("changed"), end]).state == "failed")
        for events in [[start, "malformed", end], [start, message("partial")],
                       [start, message("partial"), event("turn.failed")],
                       [start, message("done"), end, message("late")],
                       [message("before start"), start, end], [start, end],
                       [start, message(String(repeating: "x", count: 32_769)), end]] {
            precondition(parse(events).state == "failed" && parse(events).text.isEmpty)
        }
        let secrets = event("item.completed", item: ["type": "reasoning", "text": "PRIVATE REASONING"])
        let warning = event("item.completed", item: ["type": "error", "message": "PRIVATE WARNING"])
        precondition(parse([warning, start, secrets, message("public"), end]).text == "public")
        for kind in ["command_execution", "mcp_tool_call", "web_search", "unknown"] {
            precondition(parse([start, event("item.started", item: ["type": kind]), end]).state == "unsafe")
        }
        precondition(parse([start, event("new_protocol_event"), end]).state == "unsafe")
        let capture = ChatCapture()
        precondition(capture.append(Data("safe".utf8)))
        precondition(!capture.append(Data(repeating: 65, count: 1_048_576)))
        precondition(!capture.append(Data("late".utf8)) && capture.text.isEmpty)
        precondition(QuickChatWorker.reasoningArguments(thinkDeeper: false).isEmpty)
        precondition(QuickChatWorker.reasoningArguments(thinkDeeper: true) == ["-c", "model_reasoning_effort=\"high\""])
        precondition(QuickChatWorker.supportedVersions.contains("0.153.4"))
        print("Complete CLI event, privacy, bounds and reasoning policy checks passed; streaming not enabled")
    }
}
