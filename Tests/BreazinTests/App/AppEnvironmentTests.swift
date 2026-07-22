import Foundation
import Testing
@testable import Breazin

@Suite("App environment isolation")
struct AppEnvironmentTests {
    @Test func environmentsHaveDistinctLocalIdentities() {
        let configurations = AppEnvironment.allCases.map(AppConfiguration.init(environment:))

        #expect(Set(configurations.map(\.bundleIdentifier)).count == configurations.count)
        #expect(Set(configurations.map(\.urlScheme)).count == configurations.count)
        #expect(Set(configurations.map(\.projectDirectoryName)).count == configurations.count)
        #expect(Set(configurations.map(\.projectTypeIdentifier)).count == configurations.count)
        #expect(Set(configurations.map(\.mcpServiceName)).count == configurations.count)
        #expect(Set(configurations.map(\.mcpPort)).count == configurations.count)
        #expect(Set(configurations.map(\.keychainService)).count == configurations.count)
        #expect(Set(configurations.map(\.cacheDirectory)).count == configurations.count)
        #expect(Set(configurations.map(\.applicationSupportDirectory)).count == configurations.count)
        #expect(Set(configurations.map(\.logDirectory)).count == configurations.count)
        #expect(Set(configurations.map(\.skillDirectory)).count == configurations.count)
    }

    @Test func productIdentityMatchesBreazinDecision() {
        let development = AppConfiguration(environment: .development)
        let staging = AppConfiguration(environment: .staging)
        let production = AppConfiguration(environment: .production)

        #expect(development.productName == "Breazin")
        #expect(staging.productName == "Breazin")
        #expect(production.productName == "Breazin")
        #expect(development.displayName == "呼息 Dev")
        #expect(staging.displayName == "呼息 Beta")
        #expect(production.displayName == "呼息")
        #expect(development.updateFeedURL == nil)
        #expect(development.uploadBrokerBaseURL.absoluteString == "http://127.0.0.1:8787")
        #expect(staging.uploadBrokerBaseURL.absoluteString == "https://uploads-staging.breazin.com")
        #expect(production.uploadBrokerBaseURL.absoluteString == "https://uploads.breazin.com")
        #expect(staging.updateFeedURL != production.updateFeedURL)
    }

    @Test func legacyProjectIdentityRemainsImportable() {
        #expect(AppConfiguration.legacyProjectFileExtension == "palmier")
        #expect(AppConfiguration.legacyProjectTypeIdentifier == "io.palmier.project")
        #expect(AppConfiguration(environment: .production).projectFileExtension == "breazin")
    }
}
