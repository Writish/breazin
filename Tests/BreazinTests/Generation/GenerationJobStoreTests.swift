import Foundation
import Testing
@testable import Breazin

@Suite("Generation job SQLite store")
struct GenerationJobStoreTests {
    @Test func cancellationWinsAgainstLateProviderSuccess() async throws {
        let store = makeStore()
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .queued, providerJobID: "remote-1")

        let requested = try await store.requestCancellation(jobID: job.id)
        #expect(requested?.cancelRequested == true)
        #expect(requested?.state == .queued)

        let lateSuccess = try await store.transition(
            jobID: job.id,
            to: .succeeded,
            providerJobID: "remote-1",
            resultURLs: ["https://example.invalid/result.mp4"]
        )
        #expect(lateSuccess?.state == .cancelled)
        #expect(try await store.recoverableJobs().isEmpty)
    }

    @Test func cancellationBeforeSubmissionBecomesTerminalWithoutRemoteCall() async throws {
        let store = makeStore()
        let job = fixtureJob()
        try await store.create(job)

        let cancelled = try await store.requestCancellation(jobID: job.id)
        #expect(cancelled?.state == .cancelled)
        #expect(cancelled?.providerJobID == nil)

        let ignored = try await store.transition(jobID: job.id, to: .running, providerJobID: "late")
        #expect(ignored?.state == .cancelled)
        #expect(ignored?.providerJobID == nil)
    }

    @Test func uploadHandleAndExpiringURLRemainBoundToJob() async throws {
        let store = makeStore()
        let job = fixtureJob()
        try await store.create(job)
        try await store.createUpload(id: "upload-1", jobID: job.id, ordinal: 0, sourceAssetID: "asset-1", mediaKind: "video")
        try await store.recordStandardizedUpload(
            id: "upload-1",
            relativePath: "job-1/upload-1.mp4",
            contentType: "video/mp4",
            contentLength: 42,
            checksumSHA256: String(repeating: "a", count: 64)
        )
        try await store.recordUploadHandle(id: "upload-1", uploadID: "remote-upload", uploadHandle: "opaque.handle")
        let urlExpiry = Date().addingTimeInterval(3_600)
        let objectExpiry = Date().addingTimeInterval(86_400)
        try await store.recordUploaded(
            id: "upload-1",
            remoteURL: "https://example.invalid/signed",
            remoteURLExpiresAt: urlExpiry,
            objectExpiresAt: objectExpiry
        )

        let upload = try #require(try await store.uploads(jobID: job.id).first)
        #expect(upload.jobID == job.id)
        #expect(upload.state == .uploaded)
        #expect(upload.uploadHandle == "opaque.handle")
        #expect(upload.checksumSHA256 == String(repeating: "a", count: 64))
        #expect(abs(try #require(upload.remoteURLExpiresAt).timeIntervalSince(urlExpiry)) < 0.01)

        try await store.recordUploadDeleted(id: "upload-1")
        let deleted = try #require(try await store.uploads(jobID: job.id).first)
        #expect(deleted.state == .deleted)
        #expect(deleted.uploadHandle == nil)
        #expect(deleted.remoteURL == nil)
    }

    @Test func staleProviderUpdateCannotRegressRunningJobToQueued() async throws {
        let store = makeStore()
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-1")

        let stale = try await store.transition(jobID: job.id, to: .queued, providerJobID: "remote-1")
        #expect(stale?.state == .running)
    }

    private func makeStore() -> GenerationJobStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-job-store-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jobs.sqlite3")
        return GenerationJobStore(databaseURL: url)
    }

    private func fixtureJob() -> NewGenerationJob {
        NewGenerationJob(
            id: "job-\(UUID().uuidString)",
            projectID: "project-1",
            placeholderAssetIDs: ["placeholder-1"],
            providerID: "volcengine-ark",
            model: "doubao-seedance-2-0-260128",
            kind: .video,
            idempotencyKey: UUID().uuidString,
            requestHash: String(repeating: "b", count: 64)
        )
    }
}
