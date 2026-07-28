import Foundation

enum TranscriptionProviderCatalog {
    static let openAI: ProviderID = "openai-transcription"
    static let defaultModel = "whisper-1"

    static var isCloudConfigured: Bool {
        ProviderCredentialStore.loadAPIKey(for: openAI) != nil
    }

    static func makeCloudProvider() throws -> any TranscriptionProvider {
        guard let key = ProviderCredentialStore.loadAPIKey(for: openAI) else {
            throw ProviderTranscriptionError.missingCredential(provider: "OpenAI transcription")
        }
        return OpenAITranscriptionProvider(apiKey: key)
    }
}

enum ProviderTranscriptionError: LocalizedError, Equatable {
    case missingCredential(provider: String)
    case unsupportedInput(String)
    case invalidResponse
    case remote(code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let provider):
            "Add the \(provider) API key in Settings > Providers."
        case .unsupportedInput(let message):
            message
        case .invalidResponse:
            "The transcription provider returned an invalid response."
        case .remote(_, let message):
            message
        }
    }
}
