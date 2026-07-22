import Foundation

extension Notification.Name {
    static let agentProviderConfigurationChanged = Notification.Name("agentProviderConfigurationChanged")
}

enum AnthropicKeychain {
    private static let providerID: ProviderID = "anthropic"
    private static let legacyAccount = "anthropic-api-key"

    static func save(_ key: String) {
        ProviderCredentialStore.saveAPIKey(key, for: providerID)
        NotificationCenter.default.post(name: .agentProviderConfigurationChanged, object: nil)
    }

    static func load() -> String? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        #endif
        if let current = ProviderCredentialStore.loadAPIKey(for: providerID) {
            return current
        }
        guard let legacy = KeychainStore.load(account: legacyAccount) else { return nil }
        ProviderCredentialStore.saveAPIKey(legacy, for: providerID)
        KeychainStore.delete(account: legacyAccount)
        return legacy
    }

    static func delete() {
        ProviderCredentialStore.deleteAPIKey(for: providerID)
        KeychainStore.delete(account: legacyAccount)
        NotificationCenter.default.post(name: .agentProviderConfigurationChanged, object: nil)
    }
}

struct AnthropicClient: AgentProvider {
    let providerID: ProviderID = "anthropic"
    let apiKey: String
    let model: AgentModel
    var maxTokens: Int = 8192

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

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
        guard !apiKey.isEmpty else { throw AnthropicClientError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: AnthropicRequestBody.build(
                model: model, maxTokens: maxTokens, system: system, tools: tools, messages: messages
            ),
            options: [.sortedKeys]
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            throw AnthropicClientError.httpError(status: http.statusCode, body: body)
        }

        try await AnthropicSSE.parse(bytes: bytes, continuation: continuation)
    }
}
