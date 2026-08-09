import Foundation

enum AppCredentialPreloader {
    static func preloadForLaunch() {
        _ = AnthropicKeychain.load()
        _ = DeepSeekKeychain.load()
        ProviderCredentialStore.preloadForLaunch()
        FeedbackCredentialStore.preloadForLaunch()
    }
}
