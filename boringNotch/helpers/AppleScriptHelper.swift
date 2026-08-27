//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum AppleScriptHelper {
    static let errorDomain = "AppleScriptError"

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
                        let errorNumber = (error["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 1
                        let errorMessage = error["NSAppleScriptErrorMessage"] as? String
                            ?? "AppleScript execution failed"
                        var userInfo = error as? [String: Any] ?? [:]
                        userInfo[NSLocalizedDescriptionKey] = errorMessage
                        continuation.resume(
                            throwing: NSError(
                                domain: errorDomain,
                                code: errorNumber,
                                userInfo: userInfo
                            )
                        )
                    } else {
                        continuation.resume(
                            throwing: NSError(
                                domain: errorDomain,
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
