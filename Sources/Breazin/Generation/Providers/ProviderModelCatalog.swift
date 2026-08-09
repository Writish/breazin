import Foundation

enum ProviderModelCatalog {
    static let volcengineArk: ProviderID = "volcengine-ark"
    static let openAI: ProviderID = "openai"
    static let midjourney: ProviderID = "midjourney"

    static let seedream5Pro = "doubao-seedream-5-0-pro-260628"
    static let seedance2 = "doubao-seedance-2-0-260128"

    static let descriptors: [ProviderDescriptor] = [
        .init(id: volcengineArk, displayName: "Volcengine Ark", authentication: .apiKey, isImplemented: true),
        .init(id: openAI, displayName: "OpenAI GPT Image 2", authentication: .oauth, isImplemented: false),
        .init(id: midjourney, displayName: "Midjourney", authentication: .discordBot, isImplemented: false),
    ]

    static func providerID(for modelID: String) -> ProviderID? {
        switch modelID {
        case seedream5Pro, seedance2: volcengineArk
        default: nil
        }
    }

    static var hasConfiguredGenerationProvider: Bool {
        ProviderCredentialStore.loadAPIKey(for: volcengineArk) != nil
    }

    static func isConfigured(for modelID: String) -> Bool {
        guard let providerID = providerID(for: modelID) else { return false }
        return ProviderCredentialStore.loadAPIKey(for: providerID) != nil
    }

    static func makeProvider(for modelID: String) throws -> any GenerationProvider {
        guard providerID(for: modelID) == volcengineArk else {
            throw ProviderGenerationError.unsupportedModel(modelID)
        }
        guard let key = ProviderCredentialStore.loadAPIKey(for: volcengineArk) else {
            throw ProviderGenerationError.missingCredential(provider: "Volcengine")
        }
        return VolcengineGenerationProvider(apiKey: key)
    }

    /// Product-owned catalog assembled from implemented provider adapters.
    /// It is available before provider network initialization.
    static let catalogEntries: [CatalogEntry] = [
        CatalogEntry(
            id: seedream5Pro,
            kind: .image,
            displayName: "Doubao Seedream 5.0 Pro",
            allowedEndpoints: [volcengineArk.rawValue],
            responseShape: .images,
            uiCapabilities: .image(ImageCaps(
                resolutions: ["1K", "2K"],
                aspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9"],
                qualities: nil,
                supportsImageReference: true,
                maxImages: 1
            ))
        ),
        CatalogEntry(
            id: seedance2,
            kind: .video,
            displayName: "Doubao Seedance 2.0",
            allowedEndpoints: [volcengineArk.rawValue],
            responseShape: .video,
            uiCapabilities: .video(VideoCaps(
                durations: Array(4...15),
                resolutions: ["480p", "720p", "1080p", "4k"],
                aspectRatios: ["adaptive", "16:9", "9:16", "1:1", "4:3", "3:4", "21:9"],
                supportsFirstFrame: true,
                supportsLastFrame: true,
                maxReferenceImages: 9,
                maxReferenceVideos: 3,
                maxReferenceAudios: 3,
                maxTotalReferences: 15,
                maxCombinedVideoRefSeconds: 15,
                maxCombinedAudioRefSeconds: 15,
                framesAndReferencesExclusive: true,
                referenceTagNoun: "reference",
                requiresSourceVideo: false,
                requiresReferenceImage: false
            ))
        ),
    ]
}
