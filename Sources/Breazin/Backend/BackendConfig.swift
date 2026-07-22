import Foundation

enum BackendConfig {
    static let clerkPublishableKey: String? = string("BreazinClerkPublishableKey")
    static let clerkKeychainAccessGroup: String? = string("BreazinClerkKeychainAccessGroup")
    static let convexDeploymentURL: URL? = string("BreazinConvexDeploymentURL").flatMap { URL(string: $0) }
    static let convexHttpURL: URL? = string("BreazinConvexHttpURL").flatMap { URL(string: $0) }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
