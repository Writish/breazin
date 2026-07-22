import Foundation

struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }

    var description: String { rawValue }
}

enum ProviderGenerationKind: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case upscale
}

struct ProviderGenerationModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kinds: Set<ProviderGenerationKind>
}

struct ProviderAssetInput: Codable, Equatable, Sendable {
    let url: URL
    let contentType: String
    let role: String?

    init(url: URL, contentType: String, role: String? = nil) {
        self.url = url
        self.contentType = contentType
        self.role = role
    }
}

enum ProviderAuthenticationKind: String, Codable, Sendable {
    case apiKey = "api_key"
    case oauth
    case discordBot = "discord_bot"
}

struct ProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: ProviderID
    let displayName: String
    let authentication: ProviderAuthenticationKind
    let isImplemented: Bool
}

struct ProviderGenerationRequest: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let kind: ProviderGenerationKind
    let model: String
    let prompt: String
    let inputs: [ProviderAssetInput]
    let options: [String: String]
}

enum ProviderGenerationState: String, Codable, Sendable {
    case queued
    case running
    case downloading
    case succeeded
    case failed
    case cancelled
    case needsAttention = "needs_attention"

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        default: false
        }
    }
}

struct ProviderGenerationJob: Codable, Equatable, Sendable {
    let providerID: ProviderID
    let providerJobID: String
    let state: ProviderGenerationState
    let resultURLs: [URL]
    let errorCode: String?
}

enum ProviderGenerationError: LocalizedError, Equatable {
    case missingCredential(provider: String)
    case unsupportedModel(String)
    case unsupportedInput(String)
    case invalidResponse
    case remote(code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let provider):
            "Add the \(provider) API key in Settings > Providers."
        case .unsupportedModel(let model):
            "Unsupported provider model: \(model)"
        case .unsupportedInput(let message):
            message
        case .invalidResponse:
            "The generation provider returned an invalid response."
        case .remote(_, let message):
            message
        }
    }
}

struct ProviderRemoteAsset: Codable, Equatable, Sendable {
    let identifier: String
    let url: URL
    let contentType: String
    let checksumSHA256: String?
}

struct ProviderTranscriptionRequest: Sendable {
    let fileURL: URL
    let preferredLocaleIdentifier: String?
    let censorProfanity: Bool
}

protocol GenerationProvider: Sendable {
    var id: ProviderID { get }
    func models() async throws -> [ProviderGenerationModel]
    func submit(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob
    func status(jobID: String) async throws -> ProviderGenerationJob
    func cancel(jobID: String) async throws
}

protocol UploadProvider: Sendable {
    var id: ProviderID { get }
    func upload(_ file: URL, contentType: String) async throws -> ProviderRemoteAsset
}

protocol TranscriptionProvider: Sendable {
    var id: ProviderID { get }
    func transcribe(_ request: ProviderTranscriptionRequest) async throws -> TranscriptionResult
}
