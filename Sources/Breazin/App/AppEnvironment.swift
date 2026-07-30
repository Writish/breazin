import Foundation

enum AppEnvironment: String, CaseIterable, Sendable {
    case development
    case staging
    case production
}

struct AppConfiguration: Equatable, Sendable {
    static let legacyProjectFileExtension = "palmier"
    static let legacyProjectTypeIdentifier = "io.palmier.project"

    let environment: AppEnvironment
    let productName: String
    let displayName: String
    let bundleIdentifier: String
    let urlScheme: String
    let projectDirectoryName: String
    let projectTypeIdentifier: String
    let projectFileExtension: String
    let mcpServiceName: String
    let mcpPort: UInt16
    let telemetryEnvironment: String
    let updateFeedURL: URL?
    let uploadBrokerBaseURL: URL
    let feedbackBaseURL: URL

    init(environment: AppEnvironment) {
        self.environment = environment
        productName = "Breazin"
        projectFileExtension = "breazin"
        telemetryEnvironment = environment.rawValue

        switch environment {
        case .development:
            displayName = "呼息 Dev"
            bundleIdentifier = "com.writish.breazin.dev"
            urlScheme = "breazin-dev"
            projectDirectoryName = "呼息 Dev"
            projectTypeIdentifier = "com.writish.breazin.project.dev"
            mcpServiceName = "breazin-dev"
            mcpPort = 19790
            updateFeedURL = nil
            uploadBrokerBaseURL = URL(string: "http://127.0.0.1:8787")!
            feedbackBaseURL = URL(string: "https://feedback-dev.breazin.com")!
        case .staging:
            displayName = "呼息 Beta"
            bundleIdentifier = "com.writish.breazin.beta"
            urlScheme = "breazin-beta"
            projectDirectoryName = "呼息 Beta"
            projectTypeIdentifier = "com.writish.breazin.project.beta"
            mcpServiceName = "breazin-beta"
            mcpPort = 19791
            updateFeedURL = URL(string: "https://raw.githubusercontent.com/Writish/breazin/main/appcast-beta.xml")
            uploadBrokerBaseURL = URL(string: "https://uploads-staging.breazin.com")!
            feedbackBaseURL = URL(string: "https://feedback-staging.breazin.com")!
        case .production:
            displayName = "呼息"
            bundleIdentifier = "com.writish.breazin"
            urlScheme = "breazin"
            projectDirectoryName = "呼息"
            projectTypeIdentifier = "com.writish.breazin.project"
            mcpServiceName = "breazin"
            mcpPort = 19789
            updateFeedURL = URL(string: "https://raw.githubusercontent.com/Writish/breazin/main/appcast.xml")
            uploadBrokerBaseURL = URL(string: "https://uploads.breazin.com")!
            feedbackBaseURL = URL(string: "https://feedback.breazin.com")!
        }
    }

    static let current = AppConfiguration(environment: configuredEnvironment())

    var userDataDirectoryName: String {
        switch environment {
        case .development: "Breazin Dev"
        case .staging: "Breazin Beta"
        case .production: "Breazin"
        }
    }

    var preferencesPrefix: String { bundleIdentifier }
    var logSubsystem: String { bundleIdentifier }
    var keychainService: String { bundleIdentifier }

    var projectStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(projectDirectoryName, isDirectory: true)
    }

    var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(userDataDirectoryName, isDirectory: true)
    }

    var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(userDataDirectoryName, isDirectory: true)
    }

    var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(userDataDirectoryName, isDirectory: true)
    }

    var skillDirectory: URL {
        let folder: String
        switch environment {
        case .development: folder = ".breazin-dev"
        case .staging: folder = ".breazin-beta"
        case .production: folder = ".breazin"
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    private static func configuredEnvironment(bundle: Bundle = .main) -> AppEnvironment {
        guard let value = bundle.object(forInfoDictionaryKey: "BreazinEnvironment") as? String,
              let environment = AppEnvironment(rawValue: value.lowercased()) else {
            return .development
        }
        return environment
    }
}
