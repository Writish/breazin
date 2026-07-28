import Foundation
import Testing
@testable import Breazin

@Suite("OpenAI transcription provider")
struct OpenAITranscriptionProviderTests {
    @Test func multipartRequestUsesBearerAuthAndWordTimestamps() async throws {
        let audioURL = try temporaryAudio(Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.example")!,
            model: "whisper-1"
        ) { request, bodyURL in
            #expect(request.url?.absoluteString == "https://api.example/v1/audio/transcriptions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=breazin-") == true)

            let body = try Data(contentsOf: bodyURL)
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
            #expect(text.contains("name=\"response_format\"\r\n\r\nverbose_json\r\n"))
            #expect(text.contains("name=\"timestamp_granularities[]\"\r\n\r\nword\r\n"))
            #expect(text.contains("name=\"timestamp_granularities[]\"\r\n\r\nsegment\r\n"))
            #expect(text.contains("name=\"language\"\r\n\r\nzh\r\n"))
            #expect(text.contains("filename=\"audio.wav\""))
            #expect(text.contains(audioURL.lastPathComponent) == false)

            return (
                Data(#"{"text":"你好","language":"zh","words":[{"word":"你好","start":0.1,"end":0.7}],"segments":[{"text":"你好","start":0.1,"end":0.7}]}"#.utf8),
                try response(url: request.url!, status: 200)
            )
        }

        let result = try await provider.transcribe(.init(
            fileURL: audioURL,
            preferredLocaleIdentifier: "zh-CN",
            censorProfanity: false
        ))

        #expect(result.text == "你好")
        #expect(result.language == "zh")
        #expect(result.words.first?.start == 0.1)
        #expect(result.segments.first?.end == 0.7)
    }

    @Test func remoteErrorPreservesProviderCodeAndMessage() async throws {
        let audioURL = try temporaryAudio(Data([0x00]))
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.example")!,
            model: "whisper-1"
        ) { request, _ in
            (
                Data(#"{"error":{"code":"invalid_api_key","message":"Incorrect API key"}}"#.utf8),
                try response(url: request.url!, status: 401)
            )
        }

        await #expect(throws: ProviderTranscriptionError.remote(
            code: "invalid_api_key",
            message: "Incorrect API key"
        )) {
            _ = try await provider.transcribe(.init(
                fileURL: audioURL,
                preferredLocaleIdentifier: nil,
                censorProfanity: false
            ))
        }
    }

    @Test func rejectsResponsesWithoutRequiredWordTimings() async throws {
        let audioURL = try temporaryAudio(Data([0x00]))
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.example")!,
            model: "whisper-1"
        ) { request, _ in
            (
                Data(#"{"text":"hello","language":"en","segments":[]}"#.utf8),
                try response(url: request.url!, status: 200)
            )
        }

        await #expect(throws: ProviderTranscriptionError.invalidResponse) {
            _ = try await provider.transcribe(.init(
                fileURL: audioURL,
                preferredLocaleIdentifier: nil,
                censorProfanity: false
            ))
        }
    }

    @Test func rejectsProfanityFilteringAndRemoteInput() async {
        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.example")!,
            model: "whisper-1"
        ) { _, _ in
            Issue.record("Transport must not run for rejected input")
            throw ProviderTranscriptionError.invalidResponse
        }

        await #expect(throws: ProviderTranscriptionError.self) {
            _ = try await provider.transcribe(.init(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                preferredLocaleIdentifier: nil,
                censorProfanity: true
            ))
        }
        await #expect(throws: ProviderTranscriptionError.self) {
            _ = try await provider.transcribe(.init(
                fileURL: URL(string: "https://example.com/audio.wav")!,
                preferredLocaleIdentifier: nil,
                censorProfanity: false
            ))
        }
    }

    private func temporaryAudio(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-transcription-test-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    private func response(url: URL, status: Int) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
    }
}
