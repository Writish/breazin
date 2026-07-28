import Foundation

enum ProviderCredentialStore {
    static let uploadBrokerAccount = "upload-broker.access-token"
    static let uploadBrokerDeviceIDAccount = "upload-broker.device-id"
    static func account(for providerID: ProviderID) -> String {
        "provider.\(providerID.rawValue).api-key"
    }

    static func saveAPIKey(_ key: String, for providerID: ProviderID) {
        KeychainStore.save(key, account: account(for: providerID))
    }

    static func loadAPIKey(for providerID: ProviderID) -> String? {
        KeychainStore.load(account: account(for: providerID))
    }

    static func deleteAPIKey(for providerID: ProviderID) {
        KeychainStore.delete(account: account(for: providerID))
    }

    static func saveUploadBrokerToken(_ token: String) {
        KeychainStore.save(token, account: uploadBrokerAccount)
    }

    static func loadUploadBrokerToken() -> String? {
        KeychainStore.load(account: uploadBrokerAccount)
    }

    static func deleteUploadBrokerToken() {
        KeychainStore.delete(account: uploadBrokerAccount)
    }

    static func uploadBrokerDeviceID() -> String {
        if let existing = KeychainStore.load(account: uploadBrokerDeviceIDAccount),
           !existing.isEmpty {
            return existing
        }
        let deviceID = UUID().uuidString.lowercased()
        KeychainStore.save(deviceID, account: uploadBrokerDeviceIDAccount)
        return deviceID
    }

    static func preloadForLaunch() {
        _ = loadAPIKey(for: ProviderModelCatalog.volcengineArk)
        _ = loadAPIKey(for: TranscriptionProviderCatalog.openAI)
        _ = loadUploadBrokerToken()
        _ = uploadBrokerDeviceID()
    }
}
