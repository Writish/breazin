import Foundation

enum DeepSeekKeychain {
    private static let providerID: ProviderID = "deepseek"

    static func save(_ key: String) {
        ProviderCredentialStore.saveAPIKey(key, for: providerID)
        NotificationCenter.default.post(name: .agentProviderConfigurationChanged, object: nil)
    }

    static func load() -> String? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        #endif
        return ProviderCredentialStore.loadAPIKey(for: providerID)
    }

    static func delete() {
        ProviderCredentialStore.deleteAPIKey(for: providerID)
        NotificationCenter.default.post(name: .agentProviderConfigurationChanged, object: nil)
    }
}

struct DeepSeekClient: AgentProvider {
    let providerID: ProviderID = "deepseek"
    let apiKey: String
    let model: AgentModel
    var maxTokens: Int = 8192

    private static let endpoint = URL(string: "https://api.deepseek.com/anthropic/v1/messages")!

    func stream(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage]
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, tools: tools, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage],
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else { throw DeepSeekClientError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: AnthropicRequestBody.build(
                model: model,
                maxTokens: maxTokens,
                system: system,
                tools: tools,
                messages: messages,
                supportsImages: false
            ),
            options: [.sortedKeys]
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            throw DeepSeekClientError.httpError(status: http.statusCode, body: body)
        }

        try await AnthropicSSE.parse(bytes: bytes, continuation: continuation)
    }
}

enum DeepSeekClientError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No DeepSeek API key is set."
        case .httpError(let status, let body): "DeepSeek API error (\(status)): \(body.prefix(500))"
        }
    }
}
