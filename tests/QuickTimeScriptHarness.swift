import AppKit
import Foundation

// Production transport methods are compiled into QuickTimeScriptHarness by the
// Python runner. Capture their scripts without sending any Apple Events.
enum AppleScriptHelper {
    static var scripts: [String] = []
    static func executeVoid(_ script: String) async throws { scripts.append(script) }
}

@main
struct QuickTimeScriptChecks {
    static func main() async {
        let controller = QuickTimeScriptHarness()
        await controller.executeDocumentCommand("play")
        await controller.executeDocumentCommand("pause")
        await controller.setDocumentProperty("current time", value: "10.5")
        await controller.setDocumentProperty("audio volume", value: "0.75")
        await controller.executeDocumentCommand("quit")
        await controller.setDocumentProperty("name", value: "1")
        await controller.setDocumentProperty("current time", value: "1; quit")
        precondition(AppleScriptHelper.scripts.count == 4)
        let expected = ["play targetDocument", "pause targetDocument",
                        "set current time of targetDocument to 10.5",
                        "set audio volume of targetDocument to 0.75",
                        "return {name, playing, current time, duration, audio volume}"]
        let scripts = AppleScriptHelper.scripts + [controller.snapshotScript()]
        for (script, statement) in zip(scripts, expected) {
            precondition(script.contains("set targetDocument to document of front window"))
            precondition(script.range(of: "document of front window")!.lowerBound
                         < script.range(of: "if playing of candidateDocument")!.lowerBound)
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script),
                  appleScript.compileAndReturnError(&error) else {
                fatalError("QuickTime script did not compile: \(String(describing: error))")
            }
            guard script.contains(statement) else {
                fatalError("Missing concrete transport statement: \(statement)")
            }
        }
        print("PASS 5 QuickTime scripts compile; unsupported inputs produce no scripts")
    }
}
