import Foundation

final class QuickChatMockProtocol: URLProtocol {
    static var statusCode = 200
    static var responseBody = """
    {"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Mock answer"}]}]}
    """
    static var holdResponse = false
    static var cancellationCount = 0
    static var failure: URLError?
    static var observedRequest: URLRequest?
    static var observedBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observedRequest = request
        if let body = request.httpBody {
            Self.observedBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            Self.observedBody = data
        }
        if Self.holdResponse { return }
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.cancellationCount += 1 }
}

@main struct QuickChatAPIHarness {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuickChatMockProtocol.self]
        let session = URLSession(configuration: configuration)
        let provider = OpenAIQuickChatProvider(model: "gpt-5-mini", session: session,
            endpoint: URL(string: "https://example.invalid/v1/responses")!, keyProvider: { "sk-test-key-not-real-123456789" })

        func body() throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: QuickChatMockProtocol.observedBody!) as! [String: Any]
        }
        func failureMessage() async -> String {
            do {
                _ = try await provider.answer(requestID: UUID(), context: "Synthetic context", thinkDeeper: false)
                preconditionFailure("Expected an API error")
            } catch { return error.localizedDescription }
        }
        let completed = QuickChatMockProtocol.responseBody
        let status = await provider.status()
        precondition(status.availability == .ready)
        let validation = await provider.validate()
        precondition(validation.availability == .ready)
        let validationBody = try body()
        precondition(validationBody["max_output_tokens"] as? Int == 1_024)
        precondition((validationBody["reasoning"] as? [String: String])?["effort"] == "minimal")
        let answer = try await provider.answer(requestID: UUID(), context: "Synthetic context", thinkDeeper: false)
        precondition(answer == "Mock answer")

        let request = QuickChatMockProtocol.observedRequest!
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key-not-real-123456789")
        let requestBody = try body()
        precondition(requestBody["model"] as? String == "gpt-5-mini")
        precondition(requestBody["store"] as? Bool == false)
        precondition(requestBody["input"] as? String == "Synthetic context")
        precondition(requestBody["tools"] == nil && requestBody["previous_response_id"] == nil)
        precondition(requestBody["max_output_tokens"] as? Int == 4_096)
        precondition((requestBody["reasoning"] as? [String: String])?["effort"] == "minimal")
        _ = try await provider.answer(requestID: UUID(), context: "Synthetic deeper context", thinkDeeper: true)
        let deeperBody = try body()
        precondition(deeperBody["max_output_tokens"] as? Int == 8_192)
        precondition((deeperBody["reasoning"] as? [String: String])?["effort"] == "low")

        let custom = OpenAIQuickChatProvider(model: "custom-model", session: session,
            endpoint: URL(string: "https://example.invalid/v1/responses")!, keyProvider: { "synthetic-key" })
        _ = try await custom.answer(requestID: UUID(), context: "Synthetic context", thinkDeeper: true)
        let customBody = try body()
        precondition(customBody["model"] as? String == "custom-model" && customBody["reasoning"] == nil)

        for response in [
            #"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial answer"}]}]}"#,
            #"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#,
            #"{"status":"failed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial answer"}]}]}"#,
            #"{"status":"completed","error":{"message":"sensitive-content"},"output":[]}"#,
            #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"sensitive-content"}]}]}"#,
            #"{"status":"completed","output":[]}"#,
            #"{"output":[{"content":[{"type":"output_text","text":"Missing status"}]}]}"#,
            "invalid JSON"
        ] {
            QuickChatMockProtocol.responseBody = response
            let message = await failureMessage()
            precondition(message.contains("OpenAI") && !message.contains("sensitive-content"))
        }
        QuickChatMockProtocol.responseBody = completed
        QuickChatMockProtocol.failure = URLError(.notConnectedToInternet)
        let offline = await provider.validate()
        precondition(offline.availability == .offline && offline.explanation.contains("network"))
        QuickChatMockProtocol.failure = nil

        QuickChatMockProtocol.statusCode = 401
        QuickChatMockProtocol.responseBody = #"{"error":{"message":"Invalid API key sk-test-key-not-real-123456789 sensitive-content"}}"#
        let rejected = await provider.validate()
        precondition(rejected.availability == .signedOut)
        precondition(rejected.explanation.contains("rejected"))
        precondition(!rejected.explanation.contains("sk-test") && !rejected.explanation.contains("sensitive-content"))
        QuickChatMockProtocol.statusCode = 429
        QuickChatMockProtocol.responseBody = #"{"error":{"code":"insufficient_quota","message":"sensitive-content"}}"#
        let quota = await provider.validate()
        precondition(quota.availability == .rateLimited && quota.explanation.contains("billing"))
        QuickChatMockProtocol.statusCode = 403
        let forbidden = await provider.validate()
        precondition(forbidden.availability == .signedOut && forbidden.explanation.contains("access"))
        QuickChatMockProtocol.statusCode = 500
        let serverFailure = await provider.validate()
        precondition(serverFailure.availability == .failed && serverFailure.explanation.contains("temporarily"))

        QuickChatMockProtocol.statusCode = 200
        QuickChatMockProtocol.responseBody = completed
        QuickChatMockProtocol.observedRequest = nil
        QuickChatMockProtocol.holdResponse = true
        let cancelled = Task { try await provider.answer(requestID: UUID(), context: "Synthetic cancellation", thinkDeeper: false) }
        for _ in 0..<100 where QuickChatMockProtocol.observedRequest == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(QuickChatMockProtocol.observedRequest != nil)
        let previousCancellations = QuickChatMockProtocol.cancellationCount
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled request returned an answer") }
        catch { precondition(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        for _ in 0..<100 where QuickChatMockProtocol.cancellationCount == previousCancellations {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(QuickChatMockProtocol.cancellationCount > previousCancellations)
        QuickChatMockProtocol.holdResponse = false

        let missing = OpenAIQuickChatProvider(model: "gpt-5-mini", session: session,
            endpoint: URL(string: "https://example.invalid/v1/responses")!, keyProvider: { nil })
        let missingStatus = await missing.status()
        precondition(missingStatus.availability == .missing)
        print("OpenAI request budgets, reasoning compatibility, completion, redaction, failures and cancellation checks passed")
    }
}
