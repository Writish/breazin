import Foundation

struct MediaManifest: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 2

    var version: Int = currentSchemaVersion
    var entries: [MediaManifestEntry] = []
    var folders: [MediaFolder] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw ProjectSchemaError.unsupportedManifestVersion(
                found: version,
                supported: Self.currentSchemaVersion
            )
        }
        version = Self.currentSchemaVersion
        entries = try c.decodeIfPresent([MediaManifestEntry].self, forKey: .entries) ?? []
        folders = try c.decodeIfPresent([MediaFolder].self, forKey: .folders) ?? []
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case version, entries, folders }
}

struct MediaManifestEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var name: String
    var type: ClipType
    var source: MediaSource
    var duration: Double
    var generationInput: GenerationInput?
    var sourceWidth: Int?
    var sourceHeight: Int?
    var sourceFPS: Double?
    var hasAudio: Bool?
    var folderId: String?
    var cachedRemoteURL: String?
    var cachedRemoteURLExpiresAt: Date?
    var generationStatus: String?
    var importInput: MediaImportInput?
}

struct MediaImportInput: Codable, Sendable, Equatable {
    var sourceURL: String? = nil
    var sourcePath: String? = nil
    var createdAt: Date? = nil
}

struct GenerationInput: Codable, Sendable, Equatable {
    var prompt: String
    var model: String
    var duration: Int
    var aspectRatio: String
    var resolution: String?
    var quality: String?
    var imageURLs: [String]?
    /// Image-only
    var numImages: Int?
    /// Audio-only
    var voice: String?
    var lyrics: String?
    var styleInstructions: String?
    var instrumental: Bool?
    var targetLanguage: String?
    /// Video-only
    var generateAudio: Bool?
    var referenceImageURLs: [String]?
    var referenceVideoURLs: [String]?
    var referenceAudioURLs: [String]?

    /// Asset IDs for the references.
    var imageURLAssetIds: [String]?
    var referenceImageAssetIds: [String]?
    var referenceVideoAssetIds: [String]?
    var referenceAudioAssetIds: [String]?
    var createdAt: Date?
    var backendJobId: String?
    /// Direct-provider routing metadata. Persisted before/after submission so recovery never resubmits blindly.
    var providerId: String?
    var providerJobId: String?
    var idempotencyKey: String?
    var outputIndex: Int?
    var resultURLs: [String]?
    /// Stable local SQLite Job reference. The project package does not own execution state.
    var localJobId: String?
}

enum MediaSource: Codable, Sendable, Equatable {
    case external(absolutePath: String)
    case project(relativePath: String)
}
