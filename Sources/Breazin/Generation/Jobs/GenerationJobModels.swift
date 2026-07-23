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
    let nextRetryAt: Date?
    let resultURLs: [String]
    let stagedOutputRelativePaths: [String]
    let errorCode: String?
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date
}

enum GenerationUploadState: String, Codable, Sendable {
    case standardizing
    case requestingUpload = "requesting_upload"
    case uploading
    case uploaded
    case failed
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
