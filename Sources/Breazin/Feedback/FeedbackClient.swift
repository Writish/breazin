import Foundation

struct FeedbackSubmission: Encodable, Sendable {
    enum Category: String, CaseIterable, Encodable, Identifiable, Sendable {
        case bug
        case feature
        case usability
        case quality
        case other

        var id: String { rawValue }
    }

    struct Consent: Encodable, Sendable {
        let diagnostics: Bool
        let followUp: Bool

        enum CodingKeys: String, CodingKey {
            case diagnostics
            case followUp = "follow_up"
        }
    }

    struct Context: Encodable, Sendable {
        let scenarioKey: String?
        let changeID: String?
        let currentJobID: String?

        enum CodingKeys: String, CodingKey {
            case scenarioKey = "scenario_key"
            case changeID = "change_id"
            case currentJobID = "current_job_id"
        }
    }

    struct TraceEvent: Encodable, Sendable {
        enum Outcome: String, Encodable, Sendable {
            case succeeded
            case failed
            case cancelled
            case abandoned
        }

        let eventName: String
        let outcome: Outcome
        let elapsedMilliseconds: Int?

        enum CodingKeys: String, CodingKey {
            case eventName = "event_name"
            case outcome
            case elapsedMilliseconds = "elapsed_ms"
        }
    }

    let clientEventID: String
    let environment: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let locale: String
    let category: Category
    let summary: String
    let description: String
    let consent: Consent
    let context: Context
    let trace: [TraceEvent]

    enum CodingKeys: String, CodingKey {
        case clientEventID = "client_event_id"
        case environment
        case appVersion = "app_version"
        case appBuild = "app_build"
        case osVersion = "os_version"
        case locale
        case category
        case summary
        case description
        case consent
        case context
        case trace
    }

    static func current(
        clientEventID: String = UUID().uuidString.lowercased(),
        category: Category,
        summary: String,
        description: String,
        consent: Consent,
        context: Context = .init(
            scenarioKey: nil,
            changeID: nil,
            currentJobID: nil
        ),
        trace: [TraceEvent] = [],
        configuration: AppConfiguration = .current,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        locale: Locale = .current
    ) -> FeedbackSubmission {
        FeedbackSubmission(
            clientEventID: clientEventID,
            environment: configuration.environment.rawValue,
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "development",
            appBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "development",
            osVersion: processInfo.operatingSystemVersionString,
            locale: locale.identifier(.bcp47),
            category: category,
            summary: summary,
            description: description,
            consent: consent,
            context: context,
            trace: trace
        )
    }

    func privacyPreview() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct FeedbackReceipt: Decodable, Sendable {
    let feedbackID: String
    let decisionID: String
    let outboxEventID: String
    let duplicate: Bool

    enum CodingKeys: String, CodingKey {
        case feedbackID = "feedbackId"
        case decisionID = "decisionId"
        case outboxEventID = "outboxEventId"
        case duplicate
    }
}

struct FeedbackDeletionReceipt: Decodable, Sendable {
    let deletionID: String
    let deletedFeedback: Int
    let deletedEvidence: Int
    let subjectSHA256: String

    enum CodingKeys: String, CodingKey {
        case deletionID = "deletionId"
        case deletedFeedback
        case deletedEvidence
        case subjectSHA256 = "subjectSha256"
    }
}

enum FeedbackClientError: LocalizedError {
    case missingCredential
    case invalidResponse
    case remote(message: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            "Feedback is not configured for this device."
        case .invalidResponse:
            "The feedback service returned an invalid response."
        case .remote(let message, let status):
            "Feedback submission failed (\(message), HTTP \(status))."
        }
    }
}

actor FeedbackClient {
    private let baseURL: URL
    private let token: String
    private let deviceID: String
    private let session: URLSession

    init(
        baseURL: URL = AppConfiguration.current.feedbackBaseURL,
        token: String? = FeedbackCredentialStore.loadToken(),
        deviceID: String = FeedbackCredentialStore.deviceID(),
        session: URLSession = .shared
    ) throws {
        guard let token, !token.isEmpty else { throw FeedbackClientError.missingCredential }
        self.baseURL = baseURL
        self.token = token
        self.deviceID = deviceID
        self.session = session
    }

    func submit(_ submission: FeedbackSubmission) async throws -> FeedbackReceipt {
        let request = try FeedbackRequestBuilder.makeRequest(
            baseURL: baseURL,
            token: token,
            deviceID: deviceID,
            submission: submission
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw FeedbackClientError.remote(
                message: envelope?.error ?? "feedback_request_failed",
                status: http.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(FeedbackReceipt.self, from: data)
        } catch {
            throw FeedbackClientError.invalidResponse
        }
    }

    func deleteMyData(rationale: String) async throws -> FeedbackDeletionReceipt {
        let request = try FeedbackRequestBuilder.makeDeletionRequest(
            baseURL: baseURL,
            token: token,
            deviceID: deviceID,
            rationale: rationale
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw FeedbackClientError.remote(
                message: envelope?.error ?? "feedback_deletion_failed",
                status: http.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(FeedbackDeletionReceipt.self, from: data)
        } catch {
            throw FeedbackClientError.invalidResponse
        }
    }
}

enum FeedbackRequestBuilder {
    static func makeRequest(
        baseURL: URL,
        token: String,
        deviceID: String,
        submission: FeedbackSubmission
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/feedback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(submission)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Breazin-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func makeDeletionRequest(
        baseURL: URL,
        token: String,
        deviceID: String,
        rationale: String
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/privacy/self-delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(
            DeletionRequest(rationale: rationale)
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Breazin-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

private struct DeletionRequest: Encodable {
    let rationale: String
}

private struct ErrorEnvelope: Decodable {
    let error: String
}
