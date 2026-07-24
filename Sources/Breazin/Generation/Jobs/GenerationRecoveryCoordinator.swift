import Foundation

/// Reconciles durable provider jobs even when no project window is open.
///
/// This coordinator never submits work. A non-terminal row without a persisted
/// provider job ID is ambiguous and is moved to `needs_attention`.
actor GenerationRecoveryCoordinator {
    static let shared = GenerationRecoveryCoordinator()

    enum RecoveryDisposition: Equatable, Sendable {
        case pollAgain
        case waitingForProject
        case stopped
        case alreadyRecovering
    }

    struct RecoverySummary: Equatable, Sendable {
        var scanned = 0
        var polling = 0
        var waitingForProject = 0
        var stopped = 0
        var alreadyRecovering = 0
    }

    typealias ProviderFactory = @Sendable (String) throws -> any GenerationProvider
    typealias StageOutputs = @Sendable (
        String,
        ProviderGenerationKind,
        [String]
    ) async throws -> [String]
    typealias Cleanup = @Sendable (String) async -> Void

    private struct RecoveryTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let store: GenerationJobStore
    private let providerFactory: ProviderFactory
    private let stageOutputs: StageOutputs
    private let cleanup: Cleanup
    private let pollInterval: Duration
    private var recoveryTasks: [String: RecoveryTask] = [:]
    private var inFlightJobIDs: Set<String> = []
    private var didStart = false

    init(
        store: GenerationJobStore = .shared,
        pollInterval: Duration = .seconds(2),
        providerFactory: @escaping ProviderFactory = { try ProviderModelCatalog.makeProvider(for: $0) },
        stageOutputs: @escaping StageOutputs = { jobID, kind, resultURLs in
            try await GenerationOutputStager.stage(
                jobID: jobID,
                kind: kind,
                resultURLs: resultURLs
            )
        },
        cleanup: @escaping Cleanup = { jobID in
            await GenerationReferenceCleanup.run(jobID: jobID)
            await GenerationOutputStager.cleanup(jobID: jobID)
        }
    ) {
        self.store = store
        self.pollInterval = pollInterval
        self.providerFactory = providerFactory
        self.stageOutputs = stageOutputs
        self.cleanup = cleanup
    }

    /// Starts app-lifetime reconciliation once. Repeated calls are idempotent.
    func start() async {
        guard !didStart else { return }
        didStart = true
        do {
            for job in try await store.recoverableJobs() {
                startRecoveryTaskIfNeeded(jobID: job.id)
            }
        } catch {
            Log.generation.error("global generation recovery scan failed")
        }
    }

    /// Performs one deterministic reconciliation pass, primarily for launch
    /// diagnostics and automated tests.
    @discardableResult
    func recoverAllOnce() async throws -> RecoverySummary {
        let jobs = try await store.recoverableJobs()
        var summary = RecoverySummary(scanned: jobs.count)
        for job in jobs {
            switch await recoverOnce(jobID: job.id) {
            case .pollAgain: summary.polling += 1
            case .waitingForProject: summary.waitingForProject += 1
            case .stopped: summary.stopped += 1
            case .alreadyRecovering: summary.alreadyRecovering += 1
            }
        }
        return summary
    }

    /// Stops app-global polling before a project-scoped service takes ownership
    /// of downloading and finalization.
    func takeOverForOpenProject(jobID: String) async {
        guard let recovery = recoveryTasks.removeValue(forKey: jobID) else { return }
        recovery.task.cancel()
        await recovery.task.value
    }

    private func startRecoveryTaskIfNeeded(jobID: String) {
        guard recoveryTasks[jobID] == nil else { return }
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runRecoveryLoop(jobID: jobID, token: token)
        }
        recoveryTasks[jobID] = RecoveryTask(token: token, task: task)
    }

    private func runRecoveryLoop(jobID: String, token: UUID) async {
        defer { recoveryFinished(jobID: jobID, token: token) }
        while !Task.isCancelled {
            switch await recoverOnce(jobID: jobID) {
            case .pollAgain:
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return
                }
            case .alreadyRecovering:
                await Task.yield()
            case .waitingForProject, .stopped:
                return
            }
        }
    }

    private func recoveryFinished(jobID: String, token: UUID) {
        guard recoveryTasks[jobID]?.token == token else { return }
        recoveryTasks.removeValue(forKey: jobID)
    }

    private func recoverOnce(jobID: String) async -> RecoveryDisposition {
        guard inFlightJobIDs.insert(jobID).inserted else { return .alreadyRecovering }
        defer { inFlightJobIDs.remove(jobID) }

        do {
            guard let job = try await store.job(id: jobID) else { return .stopped }
            if job.state.isTerminal { return .stopped }
            if job.isLegacySynchronousImageTimeout {
                _ = try await store.transition(
                    jobID: job.id,
                    to: .failed,
                    errorCode: "provider_response_timed_out",
                    errorMessage: ProviderSubmissionFailurePolicy.synchronousImageTimeoutMessage
                )
                await cleanup(job.id)
                return .stopped
            }
            if job.state == .needsAttention { return .stopped }

            if job.cancelRequested {
                if let providerJobID = job.providerJobID, !providerJobID.isEmpty {
                    do {
                        let provider = try providerFactory(job.model)
                        try await provider.cancel(jobID: providerJobID)
                    } catch {
                        Log.generation.warning("provider cancellation could not be confirmed during recovery")
                    }
                }
                _ = try await store.transition(
                    jobID: job.id,
                    to: .cancelled,
                    providerJobID: job.providerJobID
                )
                await cleanup(job.id)
                return .stopped
            }

            guard let providerJobID = job.providerJobID, !providerJobID.isEmpty else {
                _ = try await store.transition(
                    jobID: job.id,
                    to: .needsAttention,
                    errorCode: "ambiguous_submission",
                    errorMessage: "No provider task ID was persisted; the request was not resubmitted."
                )
                return .stopped
            }

            if job.state == .finalizing, !job.stagedOutputRelativePaths.isEmpty {
                return .waitingForProject
            }

            if job.state == .downloading, !job.resultURLs.isEmpty {
                return try await stage(job)
            }

            let provider = try providerFactory(job.model)
            let remote = try await provider.status(jobID: providerJobID)
            try await store.recordProviderDetails(jobID: job.id, details: remote.details)
            let updated = try await store.transition(
                jobID: job.id,
                to: GenerationJobState(providerState: remote.state),
                providerJobID: providerJobID,
                resultURLs: remote.resultURLs.map(\.absoluteString),
                errorCode: remote.errorCode,
                errorMessage: remote.details?.errorMessage
            )

            guard let updated else { return .stopped }
            if updated.state == .cancelled {
                await cleanup(job.id)
                return .stopped
            }

            switch remote.state {
            case .succeeded:
                return try await stage(updated)
            case .failed, .cancelled:
                await cleanup(job.id)
                return .stopped
            case .needsAttention:
                return .stopped
            case .queued, .running, .downloading:
                return .pollAgain
            }
        } catch is CancellationError {
            return .stopped
        } catch let error as ProviderGenerationError {
            switch error {
            case .missingCredential, .unsupportedModel:
                _ = try? await store.transition(
                    jobID: jobID,
                    to: .needsAttention,
                    errorCode: "recovery_provider_unavailable",
                    errorMessage: error.localizedDescription
                )
                return .stopped
            case .unsupportedInput, .invalidResponse, .remote:
                Log.generation.warning("global generation recovery status check failed; will retry")
                return .pollAgain
            }
        } catch {
            Log.generation.warning("global generation recovery status check failed; will retry")
            return .pollAgain
        }
    }

    private func stage(_ job: GenerationJobRecord) async throws -> RecoveryDisposition {
        guard !job.resultURLs.isEmpty else {
            _ = try await store.transition(
                jobID: job.id,
                to: .needsAttention,
                errorCode: "missing_provider_output",
                errorMessage: "The provider reported success without a downloadable output."
            )
            return .stopped
        }
        let relativePaths = try await stageOutputs(job.id, job.kind, job.resultURLs)
        guard !relativePaths.isEmpty else { throw ProviderGenerationError.invalidResponse }
        let staged = try await store.transition(
            jobID: job.id,
            to: .finalizing,
            stagedOutputRelativePaths: relativePaths
        )
        if staged?.state == .cancelled {
            await cleanup(job.id)
            return .stopped
        }
        return .waitingForProject
    }

}
