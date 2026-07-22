import Foundation
import Testing
@testable import Breazin

@Suite("Volcengine generation provider", .serialized)
struct VolcengineGenerationProviderTests {
    @Test func imageSubmissionUsesBearerAuthAndReturnsURLs() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/v3/images/generations")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let body = try #require(requestBody(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == ProviderModelCatalog.seedream5Pro)
            #expect(json["prompt"] as? String == "a calm lake")
            #expect(json["size"] as? String == "2K")
            #expect(json["response_format"] as? String == "url")
            return (200, #"{"data":[{"url":"https://assets.example/image.png"}]}"#)
        }
        let provider = VolcengineGenerationProvider(apiKey: "test-key", session: session)
        let job = try await provider.submit(.init(
            idempotencyKey: "idem-1",
            kind: .image,
            model: ProviderModelCatalog.seedream5Pro,
            prompt: "a calm lake",
            inputs: [],
            options: ["size": "2K"]
        ))

        #expect(job.state == .succeeded)
        #expect(job.providerJobID == "image-idem-1")
        #expect(job.resultURLs.map(\.absoluteString) == ["https://assets.example/image.png"])
    }

    @Test func videoSubmissionEncodesContentRolesThenPolls() async throws {
        let calls = LockedCounter()
        let session = makeSession { request in
            if calls.increment() == 1 {
                #expect(request.url?.path == "/api/v3/contents/generations/tasks")
                let body = try #require(requestBody(request))
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["model"] as? String == ProviderModelCatalog.seedance2)
                #expect(json["duration"] as? Int == 5)
                #expect(json["ratio"] as? String == "16:9")
                let content = try #require(json["content"] as? [[String: Any]])
                #expect(content.first?["type"] as? String == "text")
                #expect(content.last?["role"] as? String == "first_frame")
                return (200, #"{"id":"task-123","status":"queued"}"#)
            }
            #expect(request.url?.path == "/api/v3/contents/generations/tasks/task-123")
            #expect(request.httpMethod == "GET")
            return (200, #"{"id":"task-123","status":"succeeded","content":{"video_url":"https://assets.example/video.mp4"}}"#)
        }
        let provider = VolcengineGenerationProvider(apiKey: "test-key", session: session)
        let firstFrame = ProviderAssetInput(
            url: URL(string: "data:image/png;base64,AA==")!,
            contentType: "image/png",
            role: "first_frame"
        )
        let submitted = try await provider.submit(.init(
            idempotencyKey: "idem-video",
            kind: .video,
            model: ProviderModelCatalog.seedance2,
            prompt: "slow camera move",
            inputs: [firstFrame],
            options: ["duration": "5", "ratio": "16:9", "resolution": "720p"]
        ))
        #expect(submitted.providerJobID == "task-123")
        #expect(submitted.state == .queued)

        let completed = try await provider.status(jobID: submitted.providerJobID)
        #expect(completed.state == .succeeded)
        #expect(completed.resultURLs.map(\.absoluteString) == ["https://assets.example/video.mp4"])
    }

    @Test func remoteErrorsPreserveCodeAndSafeMessage() async throws {
        let session = makeSession { _ in
            (400, #"{"error":{"code":"InvalidParameter","message":"duration is invalid"}}"#)
        }
        let provider = VolcengineGenerationProvider(apiKey: "test-key", session: session)
        await #expect(throws: ProviderGenerationError.remote(
            code: "InvalidParameter",
            message: "duration is invalid"
        )) {
            _ = try await provider.submit(.init(
                idempotencyKey: "idem-bad",
                kind: .video,
                model: ProviderModelCatalog.seedance2,
                prompt: "test",
                inputs: [],
                options: [:]
            ))
        }
    }

    @Test func cancellationAndExpiryReachTerminalStates() async throws {
        let calls = LockedCounter()
        let session = makeSession { request in
            if calls.increment() == 1 {
                #expect(request.httpMethod == "DELETE")
                #expect(request.url?.path == "/api/v3/contents/generations/tasks/task-cancel")
                return (204, "")
            }
            #expect(request.httpMethod == "GET")
            return (200, #"{"id":"task-cancel","status":"expired","error":{"code":"TaskExpired","message":"expired"}}"#)
        }
        let provider = VolcengineGenerationProvider(apiKey: "test-key", session: session)
        try await provider.cancel(jobID: "task-cancel")
        let expired = try await provider.status(jobID: "task-cancel")
        #expect(expired.state == .failed)
        #expect(expired.errorCode == "TaskExpired")
    }

    @Test func requestBuilderMapsVideoRoles() throws {
        let params = VideoGenerationParams(
            prompt: "test",
            duration: 8,
            aspectRatio: "9:16",
            resolution: "1080p",
            startFrameURL: "data:image/png;base64,AA==",
            endFrameURL: "https://assets.example/end.png",
            referenceImageURLs: ["https://assets.example/ref.webp"],
            generateAudio: false
        )
        let request = try ProviderRequestBuilder.make(
            model: ProviderModelCatalog.seedance2,
            params: .video(params),
            idempotencyKey: "idem-builder"
        )
        #expect(request.inputs.map(\.role) == ["first_frame", "last_frame", "reference_image"])
        #expect(request.options["duration"] == "8")
        #expect(request.options["generateAudio"] == "false")
    }

    @Test func providerCatalogKeepsFutureAuthBoundariesExplicit() {
        #expect(ProviderModelCatalog.providerID(for: ProviderModelCatalog.seedream5Pro) == .init(rawValue: "volcengine-ark"))
        #expect(ProviderModelCatalog.descriptors.map(\.authentication) == [.apiKey, .oauth, .discordBot])
        #expect(ProviderModelCatalog.descriptors.map(\.isImplemented) == [true, false, false])
    }

    @MainActor
    @Test func providerRecoveryMetadataSurvivesManifestRoundTrip() throws {
        let input = GenerationInput(
            prompt: "test",
            model: ProviderModelCatalog.seedance2,
            duration: 5,
            aspectRatio: "16:9",
            resolution: "720p",
            providerId: ProviderModelCatalog.volcengineArk.rawValue,
            providerJobId: "task-recover",
            idempotencyKey: "idem-recover"
        )
        let restored = try JSONDecoder().decode(
            GenerationInput.self,
            from: JSONEncoder().encode(input)
        )
        #expect(restored.providerId == "volcengine-ark")
        #expect(restored.providerJobId == "task-recover")
        #expect(restored.idempotencyKey == "idem-recover")

        let asset = MediaAsset(
            id: "recovering",
            url: URL(fileURLWithPath: "/tmp/recovering.mp4"),
            type: .video,
            name: "Recovering",
            duration: 5,
            generationInput: restored
        )
        asset.generationStatus = .generating
        #expect(asset.canResumeGeneration)
        #expect(asset.isRecoveringGeneration)
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (Int, String)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = Self.handler ?? { _ in throw ProviderGenerationError.invalidResponse }
            let (status, payload) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(payload.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
