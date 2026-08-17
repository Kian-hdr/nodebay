//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum AppleScriptHelper {
    /// `NSAppleScript` compilation is not safe to run concurrently. Keeping all
    /// scripting work on one private queue prevents independent media sources
    /// from entering the AppleScript parser at the same time.
    private static let executionQueue = DispatchQueue(
        label: "app.nodebay.applescript",
        qos: .userInitiated
    )

    @discardableResult
    static func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                autoreleasepool {
                    let script = NSAppleScript(source: scriptText)
                    var error: NSDictionary?
                    if let descriptor = script?.executeAndReturnError(&error) {
                        continuation.resume(returning: descriptor)
                    } else if let error {
                        continuation.resume(
                            throwing: NSError(
                                domain: "AppleScriptError",
                                code: 1,
                                userInfo: error as? [String: Any]
                                    ?? [NSLocalizedDescriptionKey: "AppleScript execution failed"]
                            )
                        )
                    } else {
                        continuation.resume(
                            throwing: NSError(
                                domain: "AppleScriptError",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
                            )
                        )
                    }
                }
            }
        }
    }
    
    static func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
