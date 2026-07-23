import Foundation
import Testing
@testable import Breazin

@Suite("Temporary reference upload lifecycle")
struct TemporaryReferenceUploaderTests {
    @Test func standardizeUploadRefreshPersistAndCleanupRemainOneJobBoundFlow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-upload-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GenerationJobStore(databaseURL: root.appendingPathComponent("jobs.sqlite3"))
        let job = NewGenerationJob(
            id: "job-upload-flow",
            projectID: "project-not-open",
            placeholderAssetIDs: ["placeholder-1"],
            providerID: ProviderModelCatalog.volcengineArk.rawValue,
            model: ProviderModelCatalog.seedance2,
            kind: .video,
            idempotencyKey: UUID().uuidString,
            requestHash: String(repeating: "e", count: 64)
        )
        try await store.create(job)

        let source = root.appendingPathComponent("source.png")
        let png = try #require(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try png.write(to: source)

        let broker = RecordingUploadBroker()
        let uploader = TemporaryReferenceUploader(
            store: store,
            client: broker,
            standardizationRoot: root.appendingPathComponent("standardized", isDirectory: true)
        )

        let initial = try await uploader.upload(
            jobID: job.id,
            ordinal: 0,
            sourceAssetID: "asset-1",
            sourceURL: source,
            type: .image
        )
        #expect(initial.assetURL.absoluteString == "https://example.invalid/initial.png")

        let persisted = try #require(try await store.uploads(jobID: job.id).first)
        #expect(persisted.jobID == job.id)
        #expect(persisted.state == .uploaded)
        #expect(persisted.contentType == "image/png")
        #expect(persisted.checksumSHA256?.count == 64)
        #expect(persisted.standardizedRelativePath?.hasPrefix("/") == false)

        let refreshed = try await uploader.freshAssetURLs(jobID: job.id, minimumLifetime: 15 * 60)
        #expect(refreshed == ["https://example.invalid/refreshed.png"])
        #expect(await broker.refreshCallCount == 1)
        #expect(try await store.uploads(jobID: job.id).first?.remoteURL == refreshed.first)

        await uploader.cleanup(jobID: job.id)
        #expect(await broker.deleteCallCount == 1)
        #expect(try await store.uploads(jobID: job.id).first?.state == .deleted)
    }
}

private actor RecordingUploadBroker: UploadBrokerServing {
    private(set) var refreshCallCount = 0
    private(set) var deleteCallCount = 0

    func reserve(
        jobID: String,
        assetID: String,
        mediaKind: String,
        asset: StandardizedReferenceAsset
    ) async throws -> UploadBrokerReservation {
        #expect(jobID == "job-upload-flow")
        #expect(assetID == "asset-1")
        #expect(mediaKind == "image")
        #expect(asset.contentType == "image/png")
        #expect(asset.contentLength > 0)
        #expect(asset.checksumSHA256.count == 64)
        return UploadBrokerReservation(
            uploadID: "broker-upload-1",
            uploadHandle: "opaque-signed-handle",
            uploadURL: try #require(URL(string: "https://example.invalid/upload")),
            uploadHeaders: ["Content-Type": "image/png"],
            uploadURLExpiresAt: Date().addingTimeInterval(15 * 60),
            objectExpiresAt: Date().addingTimeInterval(2 * 24 * 60 * 60)
        )
    }

    func upload(fileURL: URL, reservation: UploadBrokerReservation) async throws {
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(reservation.uploadID == "broker-upload-1")
    }

    func complete(uploadHandle: String) async throws -> UploadBrokerAsset {
        #expect(uploadHandle == "opaque-signed-handle")
        return UploadBrokerAsset(
            uploadID: "broker-upload-1",
            assetURL: try #require(URL(string: "https://example.invalid/initial.png")),
            assetURLExpiresAt: Date().addingTimeInterval(60),
            objectExpiresAt: Date().addingTimeInterval(2 * 24 * 60 * 60)
        )
    }

    func refresh(uploadHandle: String) async throws -> UploadBrokerAsset {
        refreshCallCount += 1
        #expect(uploadHandle == "opaque-signed-handle")
        return UploadBrokerAsset(
            uploadID: "broker-upload-1",
            assetURL: try #require(URL(string: "https://example.invalid/refreshed.png")),
            assetURLExpiresAt: Date().addingTimeInterval(6 * 60 * 60),
            objectExpiresAt: Date().addingTimeInterval(2 * 24 * 60 * 60)
        )
    }

    func delete(uploadHandle: String) async throws {
        deleteCallCount += 1
        #expect(uploadHandle == "opaque-signed-handle")
    }
}
