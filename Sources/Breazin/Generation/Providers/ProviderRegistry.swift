import Foundation

actor ProviderRegistry {
    static let shared = ProviderRegistry()

    private var generationProviders: [ProviderID: any GenerationProvider] = [:]
    private var uploadProviders: [ProviderID: any UploadProvider] = [:]
    private var transcriptionProviders: [ProviderID: any TranscriptionProvider] = [:]

    func register(_ provider: any GenerationProvider) {
        generationProviders[provider.id] = provider
    }

    func register(_ provider: any UploadProvider) {
        uploadProviders[provider.id] = provider
    }

    func register(_ provider: any TranscriptionProvider) {
        transcriptionProviders[provider.id] = provider
    }

    func generationProvider(id: ProviderID) -> (any GenerationProvider)? {
        generationProviders[id]
    }

    func uploadProvider(id: ProviderID) -> (any UploadProvider)? {
        uploadProviders[id]
    }

    func transcriptionProvider(id: ProviderID) -> (any TranscriptionProvider)? {
        transcriptionProviders[id]
    }

    func generationProviderIDs() -> [ProviderID] {
        generationProviders.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
