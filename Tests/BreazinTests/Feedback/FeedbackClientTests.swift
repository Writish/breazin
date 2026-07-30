import Foundation
import Testing
@testable import Breazin

@Suite("Feedback client")
struct FeedbackClientTests {
    @Test("request contains only the feedback whitelist and device authority")
    func requestContract() throws {
        let submission = FeedbackSubmission(
            clientEventID: "event-1",
            environment: "staging",
            appVersion: "0.6.13",
            appBuild: "42",
            osVersion: "26.5.1",
            locale: "zh-Hans",
            category: .bug,
            summary: "Generation stayed active",
            description: "The progress indicator never stopped.",
            consent: .init(diagnostics: true, followUp: false),
            context: .init(
                scenarioKey: "generation.timeout",
                changeID: "CHG-0001",
                currentJobID: "job-1"
            ),
            trace: [
                .init(eventName: "generation.timeout", outcome: .failed, elapsedMilliseconds: 300_000)
            ]
        )

        let request = try FeedbackRequestBuilder.makeRequest(
            baseURL: URL(string: "https://feedback-staging.breazin.com")!,
            token: "device-token",
            deviceID: "device-1",
            submission: submission
        )
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(request.url?.absoluteString == "https://feedback-staging.breazin.com/v1/feedback")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token")
        #expect(request.value(forHTTPHeaderField: "X-Breazin-Device-ID") == "device-1")
        #expect(object["client_event_id"] as? String == "event-1")
        let consent = try #require(object["consent"] as? [String: Any])
        let context = try #require(object["context"] as? [String: Any])
        #expect(consent["follow_up"] as? Bool == false)
        #expect(consent["followUp"] == nil)
        #expect(context["scenario_key"] as? String == "generation.timeout")
        #expect(context["change_id"] as? String == "CHG-0001")
        #expect(context["current_job_id"] as? String == "job-1")
        #expect(object["raw_prompt"] == nil)
        #expect(object["project_path"] == nil)
        #expect(object["authorization"] == nil)
    }

    @Test("missing feedback authority is rejected before network access")
    func missingCredential() {
        #expect(throws: FeedbackClientError.self) {
            try FeedbackClient(
                baseURL: URL(string: "https://feedback-staging.breazin.com")!,
                token: nil,
                deviceID: "device-1",
                session: .shared
            )
        }
    }

    @Test("privacy preview is the exact whitelisted request payload")
    func privacyPreview() throws {
        let submission = FeedbackSubmission.current(
            clientEventID: "event-preview-1",
            category: .usability,
            summary: "Preview the payload",
            description: "The user should see every transmitted field.",
            consent: .init(diagnostics: true, followUp: false),
            configuration: AppConfiguration(environment: .development)
        )

        let preview = try submission.privacyPreview()
        let request = try FeedbackRequestBuilder.makeRequest(
            baseURL: URL(string: "http://127.0.0.1:8790")!,
            token: "device-token",
            deviceID: "device-1",
            submission: submission
        )
        let requestBody = try #require(request.httpBody)

        let previewObject = try #require(
            JSONSerialization.jsonObject(with: Data(preview.utf8)) as? NSDictionary
        )
        let requestObject = try #require(
            JSONSerialization.jsonObject(with: requestBody) as? NSDictionary
        )
        #expect(previewObject == requestObject)
        #expect(preview.contains(#""environment" : "development""#))
        #expect(!preview.contains("project_path"))
        #expect(!preview.contains("raw_prompt"))
    }

    @Test("self deletion derives subject from device authority")
    func deletionRequest() throws {
        let request = try FeedbackRequestBuilder.makeDeletionRequest(
            baseURL: URL(string: "https://feedback-staging.breazin.com")!,
            token: "device-token",
            deviceID: "device-1",
            rationale: "User confirmed deletion in Settings."
        )
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(request.url?.path == "/v1/privacy/self-delete")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token")
        #expect(request.value(forHTTPHeaderField: "X-Breazin-Device-ID") == "device-1")
        #expect(object["rationale"] as? String == "User confirmed deletion in Settings.")
        #expect(object["subject"] == nil)
        #expect(object["device_id"] == nil)
    }
}
