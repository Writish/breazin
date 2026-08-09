import Foundation
import Testing
@testable import Breazin

@Suite("Recovered provider output staging", .serialized)
struct GenerationOutputStagerTests {
    @Test func downloadsToJobScopedRelativePathAndCleansUp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-output-stager-\(UUID().uuidString)", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OutputFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OutputFixtureURLProtocol.payload = Data("provider-output".utf8)
        OutputFixtureURLProtocol.statusCode = 200

        let paths = try await GenerationOutputStager.stage(
            jobID: "job-output",
            kind: .video,
            resultURLs: ["https://example.invalid/generated.mp4"],
            session: session,
            root: root
        )

        #expect(paths == ["job-output/0.mp4"])
        let fileURL = try #require(GenerationOutputStager.fileURL(relativePath: paths[0], root: root))
        #expect(try Data(contentsOf: fileURL) == OutputFixtureURLProtocol.payload)
        #expect(GenerationOutputStager.fileURL(relativePath: "../outside", root: root) == nil)

        await GenerationOutputStager.cleanup(jobID: "job-output", root: root)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let sentinel = root.deletingLastPathComponent()
            .appendingPathComponent("keep-\(UUID().uuidString)")
        try Data("keep".utf8).write(to: sentinel)
        await GenerationOutputStager.cleanup(jobID: "..", root: root)
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        try FileManager.default.removeItem(at: sentinel)
    }

    @Test func rejectsNonSuccessProviderDownload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-output-stager-\(UUID().uuidString)", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OutputFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OutputFixtureURLProtocol.payload = Data("not-media".utf8)
        OutputFixtureURLProtocol.statusCode = 403

        await #expect(throws: ProviderGenerationError.invalidResponse) {
            try await GenerationOutputStager.stage(
                jobID: "job-denied",
                kind: .video,
                resultURLs: ["https://example.invalid/expired.mp4"],
                session: session,
                root: root
            )
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("job-denied").path))
    }
}

private final class OutputFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "video/mp4"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
