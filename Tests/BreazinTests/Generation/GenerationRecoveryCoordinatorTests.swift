import Foundation
import Testing
@testable import Breazin

@Suite("Global generation recovery coordinator")
struct GenerationRecoveryCoordinatorTests {
    @Test func crashRecoveryUsesDurableProviderIDWithoutResubmitting() async throws {
        let databaseURL = makeDatabaseURL()
        let beforeCrash = GenerationJobStore(databaseURL: databaseURL)
        let job = fixtureJob()
        try await beforeCrash.create(job)
        _ = try await beforeCrash.transition(jobID: job.id, to: .submitting)
        _ = try await beforeCrash.transition(jobID: job.id, to: .queued, providerJobID: "remote-crash")

        let afterCrash = GenerationJobStore(databaseURL: databaseURL)
        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-crash",
                state: .running,
                resultURLs: [],
                errorCode: nil
            )]
        )
        let coordinator = makeCoordinator(store: afterCrash, provider: provider)

        let summary = try await coordinator.recoverAllOnce()

        #expect(summary.scanned == 1)
        #expect(summary.polling == 1)
        #expect(try await afterCrash.job(id: job.id)?.state == .running)
        #expect(await provider.submitCallCount == 0)
        #expect(await provider.statusCallCount == 1)
    }

    @Test func duplicateRecoveryPassesDoNotPollTheSameJobTwice() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-duplicate")

        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-duplicate",
                state: .running,
                resultURLs: [],
                errorCode: nil
            )],
            blockStatus: true
        )
        let coordinator = makeCoordinator(store: store, provider: provider)

        async let first = coordinator.recoverAllOnce()
        await provider.waitUntilStatusStarted()
        async let duplicate = coordinator.recoverAllOnce()
        await provider.releaseStatus()

        let summaries = try await [first, duplicate]
        #expect(await provider.statusCallCount == 1)
        #expect(summaries.reduce(0) { $0 + $1.alreadyRecovering } == 1)
    }

    @Test func unopenedProjectStopsAtDurableDownloadingState() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob(projectID: "project-not-open")
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-success")

        let resultURL = try #require(URL(string: "https://example.invalid/generated.mp4"))
        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-success",
                state: .succeeded,
                resultURLs: [resultURL],
                errorCode: nil
            )]
        )
        let coordinator = makeCoordinator(store: store, provider: provider)

        let summary = try await coordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(summary.waitingForProject == 1)
        #expect(recovered.projectID == "project-not-open")
        #expect(recovered.state == .finalizing)
        #expect(recovered.resultURLs == [resultURL.absoluteString])
        #expect(recovered.stagedOutputRelativePaths == ["\(job.id)/0.mp4"])
    }

    @Test func downloadingJobWithResultsDoesNotCallProviderAgain() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(
            jobID: job.id,
            to: .downloading,
            providerJobID: "remote-downloading",
            resultURLs: ["https://example.invalid/generated.mp4"]
        )
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(store: store, provider: provider)

        let summary = try await coordinator.recoverAllOnce()

        #expect(summary.waitingForProject == 1)
        #expect(await provider.statusCallCount == 0)
        #expect(try await store.job(id: job.id)?.state == .finalizing)
    }

    @Test func providerSuccessWithoutOutputNeedsAttentionInsteadOfPollingForever() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-empty")
        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-empty",
                state: .succeeded,
                resultURLs: [],
                errorCode: nil
            )]
        )
        let coordinator = makeCoordinator(store: store, provider: provider)

        let summary = try await coordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(summary.stopped == 1)
        #expect(recovered.state == .needsAttention)
        #expect(recovered.errorCode == "missing_provider_output")
        #expect(await provider.statusCallCount == 1)
    }

    @Test func missingProviderIDNeedsAttentionAndNeverSubmits() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .queued)
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(store: store, provider: provider)

        _ = try await coordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(recovered.state == .needsAttention)
        #expect(recovered.errorCode == "ambiguous_submission")
        #expect(await provider.submitCallCount == 0)
        #expect(await provider.statusCallCount == 0)
    }

    @Test func legacySynchronousImageTimeoutBecomesTerminalWithoutRemoteRetry() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = NewGenerationJob(
            id: "job-\(UUID().uuidString)",
            projectID: "project-1",
            placeholderAssetIDs: ["placeholder-1"],
            providerID: ProviderModelCatalog.volcengineArk.rawValue,
            model: ProviderModelCatalog.seedream5Pro,
            kind: .image,
            idempotencyKey: UUID().uuidString,
            requestHash: String(repeating: "c", count: 64)
        )
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(
            jobID: job.id,
            to: .needsAttention,
            errorCode: "provider_submission_ambiguous",
            errorMessage: "The request timed out."
        )
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(store: store, provider: provider)

        let summary = try await coordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(summary.stopped == 1)
        #expect(recovered.state == .failed)
        #expect(recovered.errorCode == "provider_response_timed_out")
        #expect(recovered.errorMessage == ProviderSubmissionFailurePolicy.synchronousImageTimeoutMessage)
        #expect(await provider.submitCallCount == 0)
        #expect(await provider.statusCallCount == 0)
    }

    @Test func cancellationWithoutProviderIDClosesLocallyWithoutSubmission() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.requestCancellation(jobID: job.id)
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(store: store, provider: provider)

        _ = try await coordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(recovered.state == .cancelled)
        #expect(recovered.cancelRequested)
        #expect(await provider.submitCallCount == 0)
        #expect(await provider.statusCallCount == 0)
        #expect(await provider.cancelCallCount == 0)
    }

    @Test func cancellationWinsWhenProviderCompletionArrivesConcurrently() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-race")

        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-race",
                state: .succeeded,
                resultURLs: [try #require(URL(string: "https://example.invalid/late.mp4"))],
                errorCode: nil
            )],
            blockStatus: true
        )
        let coordinator = makeCoordinator(store: store, provider: provider)

        async let recovery = coordinator.recoverAllOnce()
        await provider.waitUntilStatusStarted()
        _ = try await store.requestCancellation(jobID: job.id)
        await provider.releaseStatus()
        _ = try await recovery

        let recovered = try #require(try await store.job(id: job.id))
        #expect(recovered.cancelRequested)
        #expect(recovered.state == .cancelled)
        #expect(try await store.recoverableJobs().isEmpty)
    }

    @Test func offlineRecoveryPausesWithoutCallingProviderOrAdvancingRetry() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-offline")
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(
            store: store,
            provider: provider,
            networkAvailable: { false }
        )

        let summary = try await coordinator.recoverAllOnce()
        let paused = try #require(try await store.job(id: job.id))

        #expect(summary.waitingForNetwork == 1)
        #expect(paused.state == .running)
        #expect(paused.errorCode == "network_offline")
        #expect(paused.retryCount == 0)
        #expect(paused.nextRetryAt == nil)
        #expect(await provider.statusCallCount == 0)
    }

    @Test func transientFailurePersistsBackoffAndDueRetryClearsSchedule() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-retry")
        let provider = ControlledGenerationProvider(
            responses: [.init(
                providerID: ProviderModelCatalog.volcengineArk,
                providerJobID: "remote-retry",
                state: .running,
                resultURLs: [],
                errorCode: nil
            )],
            statusFailures: 1
        )
        let policy = GenerationRetryPolicy(
            baseDelay: 10,
            maximumDelay: 100,
            jitterRatio: 0.2,
            offlinePollInterval: 5
        )
        let first = makeCoordinator(
            store: store,
            provider: provider,
            retryPolicy: policy,
            now: { Date(timeIntervalSince1970: 1_000) },
            jitterUnit: { 0.5 }
        )

        let firstSummary = try await first.recoverAllOnce()
        let scheduled = try #require(try await store.job(id: job.id))

        #expect(firstSummary.waitingForRetry == 1)
        #expect(scheduled.retryCount == 1)
        #expect(scheduled.nextRetryAt == Date(timeIntervalSince1970: 1_010))
        #expect(scheduled.errorCode == "recovery_retry_scheduled")
        #expect(await provider.statusCallCount == 1)

        let early = makeCoordinator(
            store: store,
            provider: provider,
            retryPolicy: policy,
            now: { Date(timeIntervalSince1970: 1_005) },
            jitterUnit: { 0.5 }
        )
        let earlySummary = try await early.recoverAllOnce()
        #expect(earlySummary.waitingForRetry == 1)
        #expect(await provider.statusCallCount == 1)

        let due = makeCoordinator(
            store: store,
            provider: provider,
            retryPolicy: policy,
            now: { Date(timeIntervalSince1970: 1_011) },
            jitterUnit: { 0.5 }
        )
        let dueSummary = try await due.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(dueSummary.polling == 1)
        #expect(recovered.state == .running)
        #expect(recovered.retryCount == 0)
        #expect(recovered.nextRetryAt == nil)
        #expect(recovered.errorCode == nil)
        #expect(await provider.statusCallCount == 2)
    }

    @Test func failedOutputDownloadRefreshesProviderURLAfterBackoff() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(
            jobID: job.id,
            to: .downloading,
            providerJobID: "remote-refresh-output",
            resultURLs: ["https://example.invalid/expired.mp4"]
        )
        let freshURL = try #require(URL(string: "https://example.invalid/fresh.mp4"))
        let successfulResponse = ProviderGenerationJob(
            providerID: ProviderModelCatalog.volcengineArk,
            providerJobID: "remote-refresh-output",
            state: .succeeded,
            resultURLs: [freshURL],
            errorCode: nil
        )
        let provider = ControlledGenerationProvider(
            responses: [successfulResponse, successfulResponse]
        )
        let policy = GenerationRetryPolicy(
            baseDelay: 10,
            maximumDelay: 100,
            jitterRatio: 0,
            offlinePollInterval: 5
        )
        let failing = GenerationRecoveryCoordinator(
            store: store,
            providerFactory: { _ in provider },
            stageOutputs: { _, _, _ in throw URLError(.networkConnectionLost) },
            cleanup: { _ in },
            retryPolicy: policy,
            networkAvailable: { true },
            now: { Date(timeIntervalSince1970: 2_000) },
            jitterUnit: { 0.5 }
        )

        let failureSummary = try await failing.recoverAllOnce()
        let scheduled = try #require(try await store.job(id: job.id))

        #expect(failureSummary.waitingForRetry == 1)
        #expect(scheduled.resultURLs.isEmpty)
        #expect(scheduled.retryCount == 1)
        #expect(await provider.statusCallCount == 0)

        let secondFailureCoordinator = GenerationRecoveryCoordinator(
            store: store,
            providerFactory: { _ in provider },
            stageOutputs: { _, _, _ in throw URLError(.networkConnectionLost) },
            cleanup: { _ in },
            retryPolicy: policy,
            networkAvailable: { true },
            now: { Date(timeIntervalSince1970: 2_011) },
            jitterUnit: { 0.5 }
        )

        let secondFailureSummary = try await secondFailureCoordinator.recoverAllOnce()
        let rescheduled = try #require(try await store.job(id: job.id))

        #expect(secondFailureSummary.waitingForRetry == 1)
        #expect(rescheduled.resultURLs.isEmpty)
        #expect(rescheduled.retryCount == 2)
        #expect(rescheduled.nextRetryAt == Date(timeIntervalSince1970: 2_031))
        #expect(await provider.statusCallCount == 1)

        let recoveredCoordinator = GenerationRecoveryCoordinator(
            store: store,
            providerFactory: { _ in provider },
            stageOutputs: { jobID, _, urls in
                #expect(urls == [freshURL.absoluteString])
                return ["\(jobID)/0.mp4"]
            },
            cleanup: { _ in },
            retryPolicy: policy,
            networkAvailable: { true },
            now: { Date(timeIntervalSince1970: 2_032) },
            jitterUnit: { 0.5 }
        )

        let recoveredSummary = try await recoveredCoordinator.recoverAllOnce()
        let recovered = try #require(try await store.job(id: job.id))

        #expect(recoveredSummary.waitingForProject == 1)
        #expect(recovered.state == .finalizing)
        #expect(recovered.resultURLs == [freshURL.absoluteString])
        #expect(recovered.retryCount == 0)
        #expect(recovered.nextRetryAt == nil)
        #expect(await provider.statusCallCount == 2)
    }

    @Test func synchronousImageDownloadRetryKeepsItsOnlyResultURL() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = NewGenerationJob(
            id: "job-\(UUID().uuidString)",
            projectID: "project-1",
            placeholderAssetIDs: ["placeholder-1"],
            providerID: ProviderModelCatalog.volcengineArk.rawValue,
            model: ProviderModelCatalog.seedream5Pro,
            kind: .image,
            idempotencyKey: UUID().uuidString,
            requestHash: String(repeating: "d", count: 64)
        )
        let resultURL = "https://example.invalid/image.png"
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(
            jobID: job.id,
            to: .downloading,
            providerJobID: "image-request-id",
            resultURLs: [resultURL]
        )
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = GenerationRecoveryCoordinator(
            store: store,
            providerFactory: { _ in provider },
            stageOutputs: { _, _, _ in throw URLError(.networkConnectionLost) },
            cleanup: { _ in },
            retryPolicy: .default,
            networkAvailable: { true },
            now: { Date(timeIntervalSince1970: 3_000) },
            jitterUnit: { 0.5 }
        )

        let summary = try await coordinator.recoverAllOnce()
        let scheduled = try #require(try await store.job(id: job.id))

        #expect(summary.waitingForRetry == 1)
        #expect(scheduled.resultURLs == [resultURL])
        #expect(scheduled.retryCount == 1)
        #expect(await provider.statusCallCount == 0)
    }

    @Test func cancellationPreemptsPersistedRetrySchedule() async throws {
        let store = GenerationJobStore(databaseURL: makeDatabaseURL())
        let job = fixtureJob()
        try await store.create(job)
        _ = try await store.transition(jobID: job.id, to: .submitting)
        _ = try await store.transition(jobID: job.id, to: .running, providerJobID: "remote-cancel-retry")
        try await store.scheduleRetry(
            jobID: job.id,
            at: Date(timeIntervalSince1970: 9_999),
            message: "temporary"
        )
        _ = try await store.requestCancellation(jobID: job.id)
        let provider = ControlledGenerationProvider(responses: [])
        let coordinator = makeCoordinator(
            store: store,
            provider: provider,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let summary = try await coordinator.recoverAllOnce()
        let cancelled = try #require(try await store.job(id: job.id))

        #expect(summary.stopped == 1)
        #expect(cancelled.state == .cancelled)
        #expect(await provider.cancelCallCount == 1)
        #expect(await provider.statusCallCount == 0)
    }

    private func makeCoordinator(
        store: GenerationJobStore,
        provider: ControlledGenerationProvider,
        retryPolicy: GenerationRetryPolicy = .default,
        networkAvailable: @escaping GenerationRecoveryCoordinator.NetworkAvailable = { true },
        now: @escaping GenerationRecoveryCoordinator.Now = { Date() },
        jitterUnit: @escaping GenerationRecoveryCoordinator.JitterUnit = { 0.5 }
    ) -> GenerationRecoveryCoordinator {
        GenerationRecoveryCoordinator(
            store: store,
            providerFactory: { _ in provider },
            stageOutputs: { jobID, _, _ in ["\(jobID)/0.mp4"] },
            cleanup: { _ in },
            retryPolicy: retryPolicy,
            networkAvailable: networkAvailable,
            now: now,
            jitterUnit: jitterUnit
        )
    }

    private func makeDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-recovery-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jobs.sqlite3")
    }

    private func fixtureJob(projectID: String = "project-1") -> NewGenerationJob {
        NewGenerationJob(
            id: "job-\(UUID().uuidString)",
            projectID: projectID,
            placeholderAssetIDs: ["placeholder-1"],
            providerID: ProviderModelCatalog.volcengineArk.rawValue,
            model: ProviderModelCatalog.seedance2,
            kind: .video,
            idempotencyKey: UUID().uuidString,
            requestHash: String(repeating: "b", count: 64)
        )
    }
}

private actor ControlledGenerationProvider: GenerationProvider {
    nonisolated let id = ProviderModelCatalog.volcengineArk

    private let responses: [ProviderGenerationJob]
    private let blockStatus: Bool
    private var remainingStatusFailures: Int
    private var nextResponseIndex = 0
    private var statusContinuation: CheckedContinuation<Void, Never>?
    private var statusStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var submitCallCount = 0
    private(set) var statusCallCount = 0
    private(set) var cancelCallCount = 0

    init(
        responses: [ProviderGenerationJob],
        blockStatus: Bool = false,
        statusFailures: Int = 0
    ) {
        self.responses = responses
        self.blockStatus = blockStatus
        remainingStatusFailures = statusFailures
    }

    func models() async throws -> [ProviderGenerationModel] {
        []
    }

    func submit(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob {
        submitCallCount += 1
        throw ProviderGenerationError.remote(code: "unexpected_submit", message: "Recovery must never submit.")
    }

    func status(jobID: String) async throws -> ProviderGenerationJob {
        statusCallCount += 1
        for continuation in statusStartedContinuations { continuation.resume() }
        statusStartedContinuations.removeAll()
        if blockStatus {
            await withCheckedContinuation { continuation in
                statusContinuation = continuation
            }
        }
        if remainingStatusFailures > 0 {
            remainingStatusFailures -= 1
            throw URLError(.timedOut)
        }
        guard responses.indices.contains(nextResponseIndex) else {
            throw ProviderGenerationError.remote(code: "missing_fixture", message: "No status fixture.")
        }
        defer { nextResponseIndex += 1 }
        return responses[nextResponseIndex]
    }

    func cancel(jobID: String) async throws {
        cancelCallCount += 1
    }

    func waitUntilStatusStarted() async {
        guard statusCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            statusStartedContinuations.append(continuation)
        }
    }

    func releaseStatus() {
        statusContinuation?.resume()
        statusContinuation = nil
    }
}
