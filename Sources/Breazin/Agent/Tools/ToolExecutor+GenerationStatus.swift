import Foundation

extension ToolExecutor {
    private static let generationStatusAllowedKeys: Set<String> = [
        "mediaRefs", "refresh", "includeCompleted",
    ]

    func getGenerationStatus(
        _ editor: EditorViewModel,
        _ args: [String: Any]
    ) async throws -> ToolResult {
        try validateUnknownKeys(
            args,
            allowed: Self.generationStatusAllowedKeys,
            path: "get_generation_status"
        )
        let requestedRefs = Set(args.stringArray("mediaRefs"))
        let generatedEntries = editor.mediaManifest.entries.filter {
            $0.generationInput?.localJobId?.isEmpty == false
        }
        if !requestedRefs.isEmpty {
            let knownRefs = Set(generatedEntries.map(\.id))
            let missing = requestedRefs.subtracting(knownRefs).sorted()
            guard missing.isEmpty else {
                throw ToolError("No direct-provider generation job for mediaRef(s): \(missing.joined(separator: ", ")).")
            }
        }

        let requestedJobIDs = Set(generatedEntries.compactMap { entry -> String? in
            guard requestedRefs.isEmpty || requestedRefs.contains(entry.id) else { return nil }
            return entry.generationInput?.localJobId
        })
        let includeCompleted = args.bool("includeCompleted") ?? true
        var jobs = try await loadGenerationJobs(
            requestedJobIDs: requestedJobIDs,
            projectID: editor.projectId,
            includeCompleted: includeCompleted
        )

        var refreshErrors: [String: String] = [:]
        if args.bool("refresh") ?? true {
            refreshErrors = await refreshProviderJobs(jobs)
            jobs = try await loadGenerationJobs(
                requestedJobIDs: requestedJobIDs,
                projectID: editor.projectId,
                includeCompleted: includeCompleted
            )
        }

        let entriesByJob = Dictionary(grouping: generatedEntries) {
            $0.generationInput?.localJobId ?? ""
        }
        let payloadJobs = jobs.map { job -> [String: Any] in
            var payload: [String: Any] = [
                "jobId": job.id,
                "mediaRefs": (entriesByJob[job.id] ?? []).map(\.id),
                "provider": job.providerID,
                "model": job.model,
                "kind": job.kind.rawValue,
                "status": job.state.rawValue,
                "createdAt": job.createdAt.ISO8601Format(),
                "updatedAt": job.updatedAt.ISO8601Format(),
                "resultURLAvailable": !job.resultURLs.isEmpty,
                "resultCount": job.resultURLs.count,
                "submissionAttempts": job.attemptCount,
                "recoveryRetries": job.retryCount,
            ]
            if let nextRetryAt = job.nextRetryAt {
                payload["nextRetryAt"] = nextRetryAt.ISO8601Format()
            }
            if let providerJobID = job.providerJobID {
                payload["providerTaskId"] = providerJobID
            }
            if let details = job.providerDetails {
                payload["providerStatus"] = details.status.rawValue
                payload["checkedAt"] = details.checkedAt.ISO8601Format()
                if let created = details.providerCreatedAt {
                    payload["providerCreatedAt"] = created.ISO8601Format()
                }
                if let updated = details.providerUpdatedAt {
                    payload["providerUpdatedAt"] = updated.ISO8601Format()
                }
                if let usage = details.usage {
                    var value: [String: Any] = [:]
                    if let count = usage.generatedImages { value["generatedImages"] = count }
                    if let count = usage.inputImages { value["inputImages"] = count }
                    if let tokens = usage.outputTokens { value["outputTokens"] = tokens }
                    if let tokens = usage.completionTokens { value["completionTokens"] = tokens }
                    if let tokens = usage.totalTokens { value["totalTokens"] = tokens }
                    if !value.isEmpty { payload["usage"] = value }
                }
                if let output = details.output {
                    var value: [String: Any] = [:]
                    if let seed = output.seed { value["seed"] = seed }
                    if let resolution = output.resolution { value["resolution"] = resolution }
                    if let ratio = output.ratio { value["ratio"] = ratio }
                    if let duration = output.durationSeconds { value["durationSeconds"] = duration }
                    if let frames = output.frames { value["frames"] = frames }
                    if let fps = output.framesPerSecond { value["framesPerSecond"] = fps }
                    if !value.isEmpty { payload["output"] = value }
                }
            }
            if let code = job.errorCode { payload["errorCode"] = code }
            if let message = job.errorMessage ?? job.providerDetails?.errorMessage {
                payload["errorMessage"] = message
            }
            if let refreshError = refreshErrors[job.id] {
                payload["refreshError"] = refreshError
            }
            return payload
        }

        guard let json = Self.jsonString(["jobs": payloadJobs]) else {
            throw ToolError("Failed to encode generation status.")
        }
        let jobBlocks = jobs.map { ToolResult.Block.generationJob(id: $0.id) }
        return ToolResult(content: [.text(json)] + jobBlocks, isError: false)
    }

    private func loadGenerationJobs(
        requestedJobIDs: Set<String>,
        projectID: String?,
        includeCompleted: Bool
    ) async throws -> [GenerationJobRecord] {
        if !requestedJobIDs.isEmpty {
            var jobs: [GenerationJobRecord] = []
            for jobID in requestedJobIDs {
                if let job = try await generationJobStore.job(id: jobID),
                   includeCompleted || !job.state.isTerminal {
                    jobs.append(job)
                }
            }
            return jobs.sorted { $0.createdAt > $1.createdAt }
        }
        guard let projectID else {
            throw ToolError("Pass mediaRefs when the current project has no durable project ID.")
        }
        return try await generationJobStore.jobs(
            projectID: projectID,
            includeTerminal: includeCompleted
        )
    }

    private func refreshProviderJobs(_ jobs: [GenerationJobRecord]) async -> [String: String] {
        let refreshable = jobs.filter {
            $0.kind == .video && $0.providerJobID?.isEmpty == false
        }
        let grouped = Dictionary(grouping: refreshable, by: \.providerID)
        var errors: [String: String] = [:]

        for group in grouped.values {
            guard let first = group.first else { continue }
            guard await GenerationConnectivityMonitor.shared.isOnline() else {
                for job in group {
                    try? await generationJobStore.recordOfflinePause(jobID: job.id)
                    errors[job.id] = "network_offline"
                }
                continue
            }
            do {
                let provider = try ProviderModelCatalog.makeProvider(for: first.model)
                let remoteJobs: [ProviderGenerationJob]
                if group.count == 1, let providerJobID = first.providerJobID {
                    remoteJobs = [try await provider.status(jobID: providerJobID)]
                } else {
                    remoteJobs = try await provider.status(
                        jobIDs: group.compactMap(\.providerJobID)
                    )
                }
                let remoteByID = Dictionary(uniqueKeysWithValues: remoteJobs.map {
                    ($0.providerJobID, $0)
                })
                for local in group {
                    guard let providerJobID = local.providerJobID,
                          let remote = remoteByID[providerJobID] else {
                        errors[local.id] = "provider_task_not_returned"
                        continue
                    }
                    try await generationJobStore.recordProviderDetails(
                        jobID: local.id,
                        details: remote.details
                    )
                    _ = try await generationJobStore.transition(
                        jobID: local.id,
                        to: GenerationJobState(providerState: remote.state),
                        providerJobID: providerJobID,
                        resultURLs: remote.resultURLs.map(\.absoluteString),
                        errorCode: remote.errorCode,
                        errorMessage: remote.details?.errorMessage,
                        resetRetryCount: remote.state != .succeeded
                    )
                }
            } catch let error as URLError where error.code == .timedOut {
                for job in group { errors[job.id] = "status_query_timed_out" }
            } catch {
                for job in group { errors[job.id] = "status_refresh_failed" }
            }
        }
        return errors
    }
}
