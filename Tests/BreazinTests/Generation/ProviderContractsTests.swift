import Foundation
import Testing
@testable import Breazin

@Suite("Provider contracts")
struct ProviderContractsTests {
    private struct FakeGenerationProvider: GenerationProvider {
        let id: ProviderID

        func models() async throws -> [ProviderGenerationModel] {
            [.init(id: "image-v1", displayName: "Image V1", kinds: [.image])]
        }

        func submit(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob {
            .init(
                providerID: id,
                providerJobID: request.idempotencyKey,
                state: .queued,
                resultURLs: [],
                errorCode: nil
            )
        }

        func status(jobID: String) async throws -> ProviderGenerationJob {
            .init(providerID: id, providerJobID: jobID, state: .running, resultURLs: [], errorCode: nil)
        }

        func cancel(jobID: String) async throws {}
    }

    @Test func credentialAccountUsesStableProviderNamespace() {
        #expect(ProviderCredentialStore.account(for: "anthropic") == "provider.anthropic.api-key")
        #expect(ProviderCredentialStore.account(for: "example-video") == "provider.example-video.api-key")
    }

    @Test func registryResolvesGenerationProvider() async throws {
        let registry = ProviderRegistry()
        let provider = FakeGenerationProvider(id: "fixture")
        await registry.register(provider)

        let resolved = await registry.generationProvider(id: "fixture")
        #expect(resolved?.id == "fixture")
        #expect(await registry.generationProviderIDs() == ["fixture"])
        #expect(try await resolved?.models().first?.id == "image-v1")
    }

    @Test func onlySuccessfulFailedAndCancelledAreTerminal() {
        #expect(ProviderGenerationState.succeeded.isTerminal)
        #expect(ProviderGenerationState.failed.isTerminal)
        #expect(ProviderGenerationState.cancelled.isTerminal)
        #expect(!ProviderGenerationState.queued.isTerminal)
        #expect(!ProviderGenerationState.needsAttention.isTerminal)
    }
}
