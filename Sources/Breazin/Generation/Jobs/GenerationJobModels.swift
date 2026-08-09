import Foundation

enum GenerationJobState: String, Codable, Sendable, CaseIterable {
    case preparing
    case submitting
    case queued
    case running
    case downloading
    case finalizing
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

    var isActivelyProcessing: Bool {
        switch self {
        case .preparing, .submitting, .queued, .running, .downloading, .finalizing: true
        case .succeeded, .failed, .cancelled, .needsAttention: false
        }
    }

    init(providerState: ProviderGenerationState) {
        self = switch providerState {
        case .queued: .queued
        case .running: .running
        case .downloading, .succeeded: .downloading
        case .failed: .failed
        case .cancelled: .cancelled
        case .needsAttention: .needsAttention
        }
    }
}

struct GenerationJobRecord: Equatable, Sendable {
    let id: String
    let projectID: String
    let placeholderAssetIDs: [String]
    let providerID: String
    let model: String
    let kind: ProviderGenerationKind
    let state: GenerationJobState
    let idempotencyKey: String
    let providerJobID: String?
    let requestHash: String
    let cancelRequested: Bool
    let attemptCount: Int
    let retryCount: Int
    let nextRetryAt: Date?
    let resultURLs: [String]
    let stagedOutputRelativePaths: [String]
    let providerDetails: ProviderGenerationDetails?
    let errorCode: String?
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date

    var isLegacySynchronousImageTimeout: Bool {
        kind == .image
            && state == .needsAttention
            && providerJobID == nil
            && errorCode == "provider_submission_ambiguous"
            && errorMessage?.localizedCaseInsensitiveContains("timed out") == true
    }

    var isOfflinePaused: Bool {
        errorCode == "network_offline"
    }

    var isRetryScheduled: Bool {
        errorCode == "recovery_retry_scheduled" && nextRetryAt != nil
    }
}

struct ProviderSubmissionFailureResolution: Equatable, Sendable {
    let state: GenerationJobState
    let code: String
    let message: String
    let shouldCleanupReferences: Bool
}

enum ProviderSubmissionFailurePolicy {
    static let synchronousImageTimeout: TimeInterval = 5 * 60
    static let synchronousImageTimeoutMessage =
        "Image generation stopped after waiting 5 minutes without a response from Volcengine. "
        + "No task ID was returned, so Breazin cannot query or cancel this request. "
        + "The provider may still have processed it; check Ark usage before retrying."

    static func resolve(
        _ error: any Error,
        kind: ProviderGenerationKind
    ) -> ProviderSubmissionFailureResolution {
        if error is CancellationError {
            return .init(
                state: .cancelled,
                code: "cancelled",
                message: "Generation cancelled",
                shouldCleanupReferences: true
            )
        }
        if let urlError = error as? URLError,
           urlError.code == .timedOut,
           kind == .image {
            return .init(
                state: .failed,
                code: "provider_response_timed_out",
                message: synchronousImageTimeoutMessage,
                shouldCleanupReferences: true
            )
        }
        if let providerError = error as? ProviderGenerationError {
            switch providerError {
            case .remote(let code, let message):
                return .init(
                    state: .failed,
                    code: code ?? "provider_rejected",
                    message: message,
                    shouldCleanupReferences: true
                )
            case .missingCredential:
                return .init(
                    state: .failed,
                    code: "provider_credential_missing",
                    message: providerError.localizedDescription,
                    shouldCleanupReferences: true
                )
            case .unsupportedModel:
                return .init(
                    state: .failed,
                    code: "provider_model_unsupported",
                    message: providerError.localizedDescription,
                    shouldCleanupReferences: true
                )
            case .unsupportedInput:
                return .init(
                    state: .failed,
                    code: "provider_input_unsupported",
                    message: providerError.localizedDescription,
                    shouldCleanupReferences: true
                )
            case .invalidResponse:
                break
            }
        }
        return .init(
            state: .needsAttention,
            code: "provider_submission_ambiguous",
            message: error.localizedDescription,
            shouldCleanupReferences: false
        )
    }
}

enum GenerationUploadState: String, Codable, Sendable {
    case standardizing
    case requestingUpload = "requesting_upload"
    case uploading
    case uploaded
    case failed
    case expired
    case deleted
}

struct GenerationUploadRecord: Equatable, Sendable {
    let id: String
    let jobID: String
    let ordinal: Int
    let sourceAssetID: String
    let mediaKind: String
    let state: GenerationUploadState
    let standardizedRelativePath: String?
    let contentType: String?
    let contentLength: Int64?
    let checksumSHA256: String?
    let uploadID: String?
    let uploadHandle: String?
    let remoteURL: String?
    let remoteURLExpiresAt: Date?
    let objectExpiresAt: Date?
    let errorCode: String?
    let createdAt: Date
    let updatedAt: Date
}

struct NewGenerationJob: Sendable {
    let id: String
    let projectID: String
    let placeholderAssetIDs: [String]
    let providerID: String
    let model: String
    let kind: ProviderGenerationKind
    let idempotencyKey: String
    let requestHash: String
}
