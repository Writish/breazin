import Foundation
import SQLite3
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

    @Test func providerStatusDetailsPersistAcrossTerminalStateAndReopen() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-job-details-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jobs.sqlite3")
        let store = GenerationJobStore(databaseURL: databaseURL)
        let job = fixtureJob()
        let details = ProviderGenerationDetails(
            status: .succeeded,
            providerCreatedAt: Date(timeIntervalSince1970: 1_784_818_800),
            providerUpdatedAt: Date(timeIntervalSince1970: 1_784_818_860),
            checkedAt: Date(timeIntervalSince1970: 1_784_818_861),
            usage: ProviderGenerationUsage(
                generatedImages: nil,
                inputImages: nil,
                outputTokens: nil,
                completionTokens: 35_800,
                totalTokens: 35_800
            ),
            output: ProviderGenerationOutput(
                seed: 42,
                resolution: "720p",
                ratio: "16:9",
                durationSeconds: 5,
                frames: nil,
                framesPerSecond: 24
            ),
            errorMessage: nil
        )
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .downloading, providerJobID: "remote-details")
        _ = try await store.transition(jobID: job.id, to: .succeeded, providerJobID: "remote-details")
        try await store.recordProviderDetails(jobID: job.id, details: details)

        let reopened = GenerationJobStore(databaseURL: databaseURL)
        let restored = try #require(try await reopened.job(id: job.id))

        #expect(restored.state == .succeeded)
        #expect(restored.providerDetails == details)
    }

    @Test func staleProviderDetailsCannotRegressRunningToQueued() async throws {
        let store = makeStore()
        let job = fixtureJob()
        try await store.create(job)
        let running = ProviderGenerationDetails(
            status: .running,
            providerCreatedAt: nil,
            providerUpdatedAt: Date(timeIntervalSince1970: 200),
            checkedAt: Date(timeIntervalSince1970: 201),
            usage: nil,
            output: nil,
            errorMessage: nil
        )
        let staleQueued = ProviderGenerationDetails(
            status: .queued,
            providerCreatedAt: nil,
            providerUpdatedAt: Date(timeIntervalSince1970: 100),
            checkedAt: Date(timeIntervalSince1970: 300),
            usage: nil,
            output: nil,
            errorMessage: nil
        )

        try await store.recordProviderDetails(jobID: job.id, details: running)
        try await store.recordProviderDetails(jobID: job.id, details: staleQueued)

        #expect(try await store.job(id: job.id)?.providerDetails == running)
    }

    @Test func versionOneDatabaseMigratesWithoutLosingJobs() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-job-store-v1-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jobs.sqlite3")
        try createVersionOneDatabase(at: databaseURL)
        let store = GenerationJobStore(databaseURL: databaseURL)
        let job = fixtureJob()

        try await store.create(job)
        let migrated = try #require(try await store.job(id: job.id))

        #expect(migrated.id == job.id)
        #expect(migrated.stagedOutputRelativePaths.isEmpty)
        #expect(migrated.providerDetails == nil)
        #expect(migrated.retryCount == 0)
        #expect(migrated.nextRetryAt == nil)
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

    private func createVersionOneDatabase(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "GenerationJobStoreTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let sql = """
            CREATE TABLE generation_jobs (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                placeholder_asset_ids TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                model TEXT NOT NULL,
                kind TEXT NOT NULL,
                state TEXT NOT NULL,
                idempotency_key TEXT NOT NULL UNIQUE,
                provider_job_id TEXT,
                request_hash TEXT NOT NULL,
                cancel_requested INTEGER NOT NULL DEFAULT 0,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                next_retry_at REAL,
                result_urls TEXT NOT NULL DEFAULT '[]',
                error_code TEXT,
                error_message TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            PRAGMA user_version = 1;
            """
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if let errorMessage { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            throw NSError(domain: "GenerationJobStoreTests", code: Int(result))
        }
    }
}
