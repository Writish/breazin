import Foundation

enum FeedbackCredentialStore {
    private static let tokenAccount = "feedback.access-token"
    private static let deviceIDAccount = "feedback.device-id"

    static func saveToken(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...512).contains(normalized.count) else { return false }
        KeychainStore.save(normalized, account: tokenAccount)
        return true
    }

    static func loadToken() -> String? {
        KeychainStore.load(account: tokenAccount)
    }

    static func deleteToken() {
        KeychainStore.delete(account: tokenAccount)
    }

    static func deviceID() -> String {
        if let existing = KeychainStore.load(account: deviceIDAccount), !existing.isEmpty {
            return existing
        }
        let identifier = UUID().uuidString.lowercased()
        KeychainStore.save(identifier, account: deviceIDAccount)
        return identifier
    }

    static func preloadForLaunch() {
        _ = loadToken()
        _ = deviceID()
    }
}
