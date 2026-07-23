import Foundation
import CryptoKit
@preconcurrency import Combine
@preconcurrency import ConvexMobile

/// Used by replace-clip callbacks so only the
/// first successful asset of an N-image generation swaps the clip
@MainActor
final class FirstOnlyFlag {
    private var fired = false
    func fire() -> Bool {
        guard !fired else { return false }
        fired = true
        return true
    }
}

@MainActor
final class GenerationService {

    private static let uploadCacheTTL: TimeInterval = 6 * 24 * 60 * 60
    private var resumedBackendJobIds: Set<String> = []
    private var resumedProviderJobIds: Set<String> = []
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let jobStore = GenerationJobStore.shared

    private struct PreparedReferences {
        let uploaded: [String]
        let tempFiles: [URL]
    }

    @discardableResult
    func generate(
        genInput: GenerationInput,
        assetType: ClipType,
        placeholderDuration: Double,
        references: [MediaAsset] = [],
        trimmedSourceOverride: TrimmedSource? = nil,
        preUploadedURLs: [String]? = nil,
        name: String? = nil,
        numImages: Int = 1,
        folderId: String? = nil,
        buildParams: @escaping ([String]) -> BackendGenerationParams,
        snapshotRefs: (@Sendable (inout GenerationInput, [String]) -> Void)? = nil,
        preprocessRef: (@Sendable (Int, MediaAsset) async throws -> URL?)? = nil,
        fileExtension: String,
        projectURL: URL?,
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)? = nil,
        onFailure: (@MainActor () -> Void)? = nil
    ) -> String {
        let count = max(1, min(4, numImages))
        let baseName = name ?? String(genInput.prompt.prefix(30))
        var routedInput = genInput
        if let providerID = ProviderModelCatalog.providerID(for: genInput.model) {
            routedInput.providerId = providerID.rawValue
            routedInput.idempotencyKey = UUID().uuidString.lowercased()
            routedInput.localJobId = UUID().uuidString.lowercased()
        }

        let resolvedFolderId = folderId.flatMap { id in
            editor.folder(id: id) != nil ? id : nil
        }
        var placeholders: [MediaAsset] = []
        let destDir = Self.destinationDirectory(for: projectURL)

        for outputIndex in 0..<count {
            var placeholderInput = routedInput
            placeholderInput.outputIndex = outputIndex
            let placeholder = createPlaceholder(
                type: assetType,
                name: baseName,
                duration: placeholderDuration,
                genInput: placeholderInput,
                folderId: resolvedFolderId,
                destDir: destDir,
                fileExtension: fileExtension,
                editor: editor
            )
            placeholders.append(placeholder)
        }
        let primaryId = placeholders[0].id

        let task = Task { @MainActor in
            defer {
                if let localJobID = routedInput.localJobId { self.activeTasks.removeValue(forKey: localJobID) }
            }
            do {
                if routedInput.providerId != nil {
                    guard let localJobID = routedInput.localJobId,
                          let providerID = routedInput.providerId,
                          let idempotencyKey = routedInput.idempotencyKey else {
                        throw ProviderGenerationError.invalidResponse
                    }
                    try await self.jobStore.create(NewGenerationJob(
                        id: localJobID,
                        projectID: editor.projectId ?? "unsaved-\(localJobID)",
                        placeholderAssetIDs: placeholders.map(\.id),
                        providerID: providerID,
                        model: routedInput.model,
                        kind: Self.providerKind(for: assetType),
                        idempotencyKey: idempotencyKey,
                        requestHash: Self.requestHash(for: routedInput)
                    ))
                    for placeholder in placeholders {
                        updateGenerationMetadata(placeholder, editor: editor, status: .generating)
                    }
                    editor.onProjectCheckpointRequired?()
                }
                let prepared = try await self.prepareReferences(
                    model: routedInput.model,
                    references: references,
                    trimmedSourceOverride: trimmedSourceOverride,
                    preUploadedURLs: preUploadedURLs,
                    preprocessRef: preprocessRef,
                    localJobID: routedInput.localJobId
                )
                defer { Self.cleanupTempFiles(prepared.tempFiles) }
                let uploaded = prepared.uploaded

                var finalGenInput = routedInput
                if let snapshotRefs {
                    snapshotRefs(&finalGenInput, uploaded)
                } else {
                    finalGenInput.imageURLs = uploaded.isEmpty ? nil : uploaded
                }
                if finalGenInput.createdAt == nil {
                    finalGenInput.createdAt = Date()
                }
                for (outputIndex, placeholder) in placeholders.enumerated() {
                    var storedInput = finalGenInput
                    storedInput.outputIndex = outputIndex
                    updateGenerationMetadata(placeholder, editor: editor) { input in
                        input = storedInput
                    }
                }

                let params = buildParams(uploaded)

                if let localJobID = finalGenInput.localJobId {
                    _ = try await self.jobStore.transition(jobID: localJobID, to: .submitting)
                }

                await self.runJob(
                    placeholders: placeholders,
                    params: params,
                    genInput: finalGenInput,
                    editor: editor,
                    onComplete: onComplete,
                    onFailure: onFailure
                )
            } catch {
                let message = error.localizedDescription
                Log.generation.error("upload failed model=\(genInput.model) error=\(message)")
                if let localJobID = routedInput.localJobId {
                    _ = try? await self.jobStore.transition(
                        jobID: localJobID,
                        to: error is CancellationError ? .cancelled : .failed,
                        errorCode: error is CancellationError ? "cancelled" : "reference_preparation_failed",
                        errorMessage: message
                    )
                }
                for placeholder in placeholders {
                    updateGenerationMetadata(placeholder, editor: editor, status: .failed("Upload failed: \(message)"))
                }
                onFailure?()
            }
        }
        if let localJobID = routedInput.localJobId { activeTasks[localJobID] = task }

        return primaryId
    }

    private func prepareReferences(
        model: String,
        references: [MediaAsset],
        trimmedSourceOverride: TrimmedSource?,
        preUploadedURLs: [String]?,
        preprocessRef: (@Sendable (Int, MediaAsset) async throws -> URL?)?,
        localJobID: String?
    ) async throws -> PreparedReferences {
        if let preUploadedURLs, !preUploadedURLs.isEmpty,
           ProviderModelCatalog.providerID(for: model) == nil || references.isEmpty {
            if ProviderModelCatalog.providerID(for: model) != nil,
               preUploadedURLs.contains(where: Self.isR2SignedURL) {
                throw ProviderGenerationError.unsupportedInput(
                    "A temporary reference URL can no longer be refreshed. Reattach the local reference media and try again."
                )
            }
            return PreparedReferences(uploaded: preUploadedURLs, tempFiles: [])
        }

        var tempFiles: [URL] = []
        do {
            var urlsToUpload = references.map(\.url)
            let refTypes = references.map(\.type)
            if let trim = trimmedSourceOverride, trim.hasTrim, !urlsToUpload.isEmpty {
                Log.generation.notice("using trimmed source: frames \(trim.trimStartFrame)+\(trim.sourceFramesConsumed)")
                let extracted = try await VideoTrimExtractor.extract(trim)
                urlsToUpload[0] = extracted
                tempFiles.append(extracted)
            }
            if let preprocessRef, !references.isEmpty {
                let rewrites = try await preprocessedReferenceURLs(references: references, preprocessRef: preprocessRef)
                for (i, rewritten) in rewrites {
                    guard let rewritten else { continue }
                    urlsToUpload[i] = rewritten
                    tempFiles.append(rewritten)
                }
            }
            let uploaded: [String]
            if ProviderModelCatalog.providerID(for: model) != nil {
                guard let localJobID else { throw ProviderGenerationError.invalidResponse }
                uploaded = try await providerReferenceURLs(
                    at: urlsToUpload,
                    types: refTypes,
                    sourceAssetIDs: references.map(\.id),
                    jobID: localJobID
                )
            } else {
                uploaded = try await uploadReferences(
                    at: urlsToUpload,
                    types: refTypes,
                    cacheKeys: uploadCacheKeys(
                        references: references,
                        trimmedFirstReference: trimmedSourceOverride?.hasTrim == true,
                        hasPreprocess: preprocessRef != nil
                    ),
                )
            }
            return PreparedReferences(uploaded: uploaded, tempFiles: tempFiles)
        } catch {
            Self.cleanupTempFiles(tempFiles)
            throw error
        }
    }

    private func providerReferenceURLs(
        at urls: [URL],
        types: [ClipType],
        sourceAssetIDs: [String],
        jobID: String
    ) async throws -> [String] {
        guard !urls.isEmpty else { return [] }
        let token = await Task.detached(priority: .utility) {
            ProviderCredentialStore.loadUploadBrokerToken()
        }.value
        let client = try UploadBrokerClient(token: token)
        let uploader = TemporaryReferenceUploader(store: jobStore, client: client)
        do {
            for (index, url) in urls.enumerated() {
                let type = types.indices.contains(index) ? types[index] : .image
                let sourceAssetID = sourceAssetIDs.indices.contains(index) ? sourceAssetIDs[index] : "reference-\(index)"
                _ = try await uploader.upload(
                    jobID: jobID,
                    ordinal: index,
                    sourceAssetID: sourceAssetID,
                    sourceURL: url,
                    type: type
                )
            }
            return try await uploader.freshAssetURLs(jobID: jobID)
        } catch {
            await uploader.cleanup(jobID: jobID)
            throw error
        }
    }

    private func preprocessedReferenceURLs(
        references: [MediaAsset],
        preprocessRef: @escaping @Sendable (Int, MediaAsset) async throws -> URL?
    ) async throws -> [(Int, URL?)] {
        try await withThrowingTaskGroup(of: (Int, URL?).self) { group in
            for (i, asset) in references.enumerated() {
                group.addTask { (i, try await preprocessRef(i, asset)) }
            }
            var results: [(Int, URL?)] = []
            for try await result in group { results.append(result) }
            return results
        }
    }

    private func uploadCacheKeys(
        references: [MediaAsset],
        trimmedFirstReference: Bool,
        hasPreprocess: Bool
    ) -> [MediaAsset?] {
        references.enumerated().map { index, asset in
            if hasPreprocess { return nil }
            if index == 0 && trimmedFirstReference { return nil }
            return asset
        }
    }

    private static func cleanupTempFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Shared

    private func createPlaceholder(
        type: ClipType,
        name: String,
        duration: Double,
        genInput: GenerationInput,
        folderId: String?,
        destDir: URL,
        fileExtension: String,
        editor: EditorViewModel
    ) -> MediaAsset {
        let id = UUID().uuidString
        let destURL = destDir.appendingPathComponent("gen-\(id.prefix(8)).\(fileExtension)")
        let placeholder = MediaAsset(
            id: id,
            url: destURL,
            type: type,
            name: name,
            duration: duration,
            generationInput: genInput
        )
        placeholder.generationStatus = .preparing
        placeholder.folderId = folderId
        editor.importMediaAsset(placeholder)
        return placeholder
    }

    private static func destinationDirectory(for projectURL: URL?) -> URL {
        if let projectURL {
            return projectURL.appendingPathComponent(Project.mediaDirectoryName, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

    @discardableResult
    private func downloadAndFinalize(asset: MediaAsset, remoteURL: URL, editor: EditorViewModel) async -> Bool {
        if asset.generationStatus != .downloading {
            updateGenerationMetadata(asset, editor: editor, status: .downloading)
        }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let realExt = remoteURL.pathExtension.lowercased()
            if !realExt.isEmpty, realExt != asset.url.pathExtension.lowercased(),
               ClipType(fileExtension: realExt) != nil {
                asset.url = asset.url.deletingPathExtension().appendingPathExtension(realExt)
            }
            asset.url = try await editor.commitStagedProjectMedia(tempURL, filename: asset.url.lastPathComponent)

            asset.pendingDownloadURL = nil
            editor.importMediaAsset(asset, skipAppend: true)
            let finalized = await editor.finalizeImportedAsset(asset)
            if finalized {
                editor.appendGenerationLog(for: asset)
            }
            return finalized
        } catch {
            let message = error.localizedDescription
            Log.generation.error("generated asset download failed error=\(message)")
            asset.pendingDownloadURL = remoteURL
            updateGenerationMetadata(asset, editor: editor, status: .failed(message))
            return false
        }
    }

    func retryDownload(asset: MediaAsset, editor: EditorViewModel) {
        guard let remoteURL = asset.pendingDownloadURL else { return }
        Task { @MainActor in
            await downloadAndFinalize(asset: asset, remoteURL: remoteURL, editor: editor)
        }
    }

    func resumePendingGenerations(editor: EditorViewModel) {
        func sorted(_ assets: [MediaAsset]) -> [MediaAsset] {
            assets.sorted {
                let left = $0.generationInput?.outputIndex ?? 0
                let right = $1.generationInput?.outputIndex ?? 0
                return left < right
            }
        }

        let pending = editor.mediaAssets.filter(\.isRecoveringGeneration)

        // A persisted idempotency key without a remote task ID is ambiguous. Never resubmit it automatically.
        for asset in editor.mediaAssets where asset.generationStatus == .generating {
            guard let input = asset.generationInput,
                  input.providerId != nil,
                  input.localJobId == nil,
                  input.idempotencyKey?.isEmpty == false,
                  input.providerJobId?.isEmpty != false else { continue }
            updateGenerationMetadata(
                asset,
                editor: editor,
                status: .failed("Submission state needs attention; Breazin did not resubmit to avoid duplicate charges.")
            )
        }

        let byBackendJob = Dictionary(grouping: pending.compactMap { asset -> (String, MediaAsset)? in
            guard let backendJobId = asset.generationInput?.backendJobId, !backendJobId.isEmpty else { return nil }
            return (backendJobId, asset)
        }, by: { $0.0 })

        for (backendJobId, group) in byBackendJob where !resumedBackendJobIds.contains(backendJobId) {
            let placeholders = sorted(group.map { $0.1 })
            resumedBackendJobIds.insert(backendJobId)
            Task { @MainActor [weak self, weak editor] in
                guard let self, let editor else { return }
                await self.monitorBackendJob(
                    backendJobId: backendJobId,
                    placeholders: placeholders,
                    editor: editor,
                    onComplete: nil,
                    onFailure: nil
                )
                self.resumedBackendJobIds.remove(backendJobId)
            }
        }


        Task { @MainActor [weak self, weak editor] in
            guard let self, let editor else { return }
            do {
                let jobs = try await self.jobStore.recoverableJobs()
                for job in jobs where job.projectID == editor.projectId {
                    await GenerationRecoveryCoordinator.shared.takeOverForOpenProject(jobID: job.id)
                    guard let job = try await self.jobStore.job(id: job.id) else { continue }
                    let placeholders = sorted(editor.mediaAssets.filter { $0.generationInput?.localJobId == job.id })
                    guard !placeholders.isEmpty else { continue }
                    if job.state == .failed || job.state == .cancelled || job.state == .needsAttention {
                        let message: String
                        switch job.state {
                        case .cancelled: message = "Generation cancelled"
                        case .needsAttention:
                            message = "Submission state needs attention; Breazin did not resubmit to avoid duplicate charges."
                        default: message = job.errorMessage ?? "Generation failed"
                        }
                        for placeholder in placeholders {
                            self.updateGenerationMetadata(placeholder, editor: editor, status: .failed(message))
                        }
                        continue
                    }
                    guard let providerJobID = job.providerJobID, !providerJobID.isEmpty else {
                        _ = try await self.jobStore.transition(
                            jobID: job.id,
                            to: .needsAttention,
                            errorCode: "ambiguous_submission",
                            errorMessage: "No provider task ID was persisted; the request was not resubmitted."
                        )
                        for placeholder in placeholders {
                            self.updateGenerationMetadata(
                                placeholder,
                                editor: editor,
                                status: .failed("Submission state needs attention; Breazin did not resubmit to avoid duplicate charges.")
                            )
                        }
                        continue
                    }
                    guard !self.resumedProviderJobIds.contains(providerJobID) else { continue }
                    self.resumedProviderJobIds.insert(providerJobID)
                    defer { self.resumedProviderJobIds.remove(providerJobID) }
                    for placeholder in placeholders {
                        self.updateGenerationMetadata(placeholder, editor: editor, status: .generating) { input in
                            input.providerJobId = providerJobID
                            input.resultURLs = job.resultURLs
                        }
                    }
                    if job.cancelRequested {
                        if let provider = try? ProviderModelCatalog.makeProvider(for: job.model) {
                            try? await provider.cancel(jobID: providerJobID)
                        }
                        _ = try await self.jobStore.transition(jobID: job.id, to: .cancelled, providerJobID: providerJobID)
                        for placeholder in placeholders {
                            self.updateGenerationMetadata(placeholder, editor: editor, status: .failed("Generation cancelled"))
                        }
                        await self.cleanupTemporaryReferences(jobID: job.id)
                    } else if job.state == .finalizing, !job.stagedOutputRelativePaths.isEmpty {
                        await self.finalizeStagedSuccess(
                            relativePaths: job.stagedOutputRelativePaths,
                            urlStrings: job.resultURLs,
                            placeholders: placeholders,
                            editor: editor,
                            onComplete: nil,
                            onFailure: nil
                        )
                    } else if job.state == .downloading, !job.resultURLs.isEmpty {
                        await self.finalizeSuccess(
                            urlStrings: job.resultURLs,
                            placeholders: placeholders,
                            editor: editor,
                            onComplete: nil,
                            onFailure: nil
                        )
                    } else {
                        let provider = try ProviderModelCatalog.makeProvider(for: job.model)
                        await self.monitorProviderJob(
                            provider: provider,
                            providerJobID: providerJobID,
                            placeholders: placeholders,
                            editor: editor,
                            onComplete: nil,
                            onFailure: nil
                        )
                    }
                }
            } catch {
                Log.generation.error("SQLite generation recovery failed")
            }
        }
    }

    private func backendError(_ error: Error) -> (code: String?, message: String) {
        struct Payload: Decodable { let code: String?; let message: String? }
        if case let ClientError.ConvexError(data) = error,
           let json = data.data(using: .utf8),
           let payload = try? JSONDecoder().decode(Payload.self, from: json),
           let message = payload.message {
            return (payload.code, message)
        }
        return (nil, error.localizedDescription)
    }

    private func updateGenerationMetadata(
        _ asset: MediaAsset,
        editor: EditorViewModel,
        status: MediaAsset.GenerationStatus? = nil,
        mutateInput: ((inout GenerationInput) -> Void)? = nil
    ) {
        if let status {
            asset.generationStatus = status
        }
        if let mutateInput, var input = asset.generationInput {
            mutateInput(&input)
            asset.generationInput = input
        }
        editor.updateManifestMetadata(for: [asset])
    }

    /// Uploads each reference and returns the hosted URLs.
    private func uploadReferences(
        at urls: [URL],
        types: [ClipType],
        cacheKeys: [MediaAsset?],
    ) async throws -> [String] {
        guard !urls.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (i, url) in urls.enumerated() {
                let type = types.indices.contains(i) ? types[i] : .image
                let cacheKey = cacheKeys.indices.contains(i) ? cacheKeys[i] : nil
                if let cacheKey, let hit = cacheKey.freshRemoteURL {
                    group.addTask { (i, hit) }
                    continue
                }
                let contentType = Self.contentType(for: url, fallback: type)
                group.addTask {
                    let uploaded = try await GenerationBackend.uploadReference(
                        fileURL: url,
                        contentType: contentType,
                    )
                    if let cacheKey {
                        await Self.recordUploadCache(asset: cacheKey, url: uploaded)
                    }
                    return (i, uploaded)
                }
            }
            var results = [(Int, String)]()
            for try await r in group { results.append(r) }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }
    }

    @MainActor
    private static func recordUploadCache(asset: MediaAsset, url: String) {
        asset.cachedRemoteURL = url
        asset.cachedRemoteURLExpiresAt = Date().addingTimeInterval(uploadCacheTTL)
    }

    private static func contentType(for url: URL, fallback: ClipType) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "aiff", "aif", "aifc": return "audio/aiff"
        case "caf": return "audio/x-caf"
        case "flac": return "audio/flac"
        default:
            switch fallback {
            case .image: return "image/jpeg"
            case .video: return "video/mp4"
            case .audio: return "audio/mpeg"
            case .text: return "application/octet-stream"
            case .lottie: return "application/json"
            case .sequence: return "video/mp4"
            }
        }
    }

    private static func isR2SignedURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.host?.hasSuffix(".r2.cloudflarestorage.com") == true
            && url.query?.contains("X-Amz-Signature=") == true
    }

    // MARK: - Job execution

    private func runJob(
        placeholders: [MediaAsset],
        params: BackendGenerationParams,
        genInput: GenerationInput,
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        if let idempotencyKey = genInput.idempotencyKey,
           ProviderModelCatalog.providerID(for: genInput.model) != nil {
            await runProviderJob(
                placeholders: placeholders,
                params: params,
                genInput: genInput,
                idempotencyKey: idempotencyKey,
                editor: editor,
                onComplete: onComplete,
                onFailure: onFailure
            )
            return
        }
        let runId = String(UUID().uuidString.prefix(8))
        Log.generation.notice("run \(runId) start model=\(genInput.model) placeholders=\(placeholders.count)")
        defer { Log.generation.notice("run \(runId) settled") }

        let jobId: String
        do {
            jobId = try await GenerationBackend.submit(
                model: genInput.model,
                params: params,
                projectId: editor.projectId,
            )
        } catch {
            let (code, message) = backendError(error)
            let expected: Set<String> = [
                "insufficient_credits", "subscription_required", "plan_required",
                "rate_limited", "invalid_params",
            ]
            if let code, expected.contains(code) {
                Log.generation.warning("submit failed model=\(genInput.model) code=\(code) error=\(message)")
            } else {
                Log.generation.error("submit failed model=\(genInput.model) error=\(message)")
            }
            for placeholder in placeholders {
                updateGenerationMetadata(placeholder, editor: editor, status: .failed(message))
            }
            onFailure?()
            return
        }

        for placeholder in placeholders {
            updateGenerationMetadata(placeholder, editor: editor, status: .generating) { input in
                input.backendJobId = jobId
            }
        }
        editor.onProjectCheckpointRequired?()

        await monitorBackendJob(
            backendJobId: jobId,
            placeholders: placeholders,
            editor: editor,
            failIfUnavailable: true,
            onComplete: onComplete,
            onFailure: onFailure
        )
    }

    private func runProviderJob(
        placeholders: [MediaAsset],
        params: BackendGenerationParams,
        genInput: GenerationInput,
        idempotencyKey: String,
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        do {
            if let localJobID = genInput.localJobId {
                _ = try await jobStore.transition(jobID: localJobID, to: .submitting, incrementAttempt: true)
            }
            let provider = try ProviderModelCatalog.makeProvider(for: genInput.model)
            let request = try ProviderRequestBuilder.make(
                model: genInput.model,
                params: params,
                idempotencyKey: idempotencyKey
            )
            let job = try await provider.submit(request)
            if let localJobID = genInput.localJobId {
                _ = try await jobStore.transition(
                    jobID: localJobID,
                    to: Self.localState(for: job.state),
                    providerJobID: job.providerJobID,
                    resultURLs: job.resultURLs.map(\.absoluteString),
                    errorCode: job.errorCode
                )
            }
            for placeholder in placeholders {
                updateGenerationMetadata(placeholder, editor: editor, status: .generating) { input in
                    input.providerId = provider.id.rawValue
                    input.providerJobId = job.providerJobID
                    input.resultURLs = job.resultURLs.map(\.absoluteString)
                }
            }
            editor.onProjectCheckpointRequired?()
            if job.state == .succeeded {
                await finalizeSuccess(
                    urlStrings: job.resultURLs.map(\.absoluteString),
                    placeholders: placeholders,
                    editor: editor,
                    onComplete: onComplete,
                    onFailure: onFailure
                )
            } else if job.state == .failed || job.state == .cancelled {
                await failProviderJob(job, placeholders: placeholders, editor: editor, onFailure: onFailure)
            } else {
                await monitorProviderJob(
                    provider: provider,
                    providerJobID: job.providerJobID,
                    placeholders: placeholders,
                    editor: editor,
                    onComplete: onComplete,
                    onFailure: onFailure
                )
            }
        } catch {
            Log.generation.error("direct provider submit failed model=\(genInput.model) error=\(error.localizedDescription)")
            if let localJobID = genInput.localJobId {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: error is CancellationError ? .cancelled : .needsAttention,
                    errorCode: error is CancellationError ? "cancelled" : "provider_submission_ambiguous",
                    errorMessage: error.localizedDescription
                )
            }
            for placeholder in placeholders {
                updateGenerationMetadata(placeholder, editor: editor, status: .failed(error.localizedDescription))
            }
            editor.onProjectCheckpointRequired?()
            onFailure?()
        }
    }

    private func monitorProviderJob(
        provider: any GenerationProvider,
        providerJobID: String,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        while !Task.isCancelled {
            do {
                let job = try await provider.status(jobID: providerJobID)
                if let localJobID = placeholders.first?.generationInput?.localJobId {
                    _ = try await jobStore.transition(
                        jobID: localJobID,
                        to: Self.localState(for: job.state),
                        providerJobID: providerJobID,
                        resultURLs: job.resultURLs.map(\.absoluteString),
                        errorCode: job.errorCode
                    )
                    if try await jobStore.job(id: localJobID)?.cancelRequested == true {
                        try? await provider.cancel(jobID: providerJobID)
                        _ = try? await jobStore.transition(jobID: localJobID, to: .cancelled, providerJobID: providerJobID)
                        for placeholder in placeholders {
                            updateGenerationMetadata(placeholder, editor: editor, status: .failed("Generation cancelled"))
                        }
                        return
                    }
                }
                switch job.state {
                case .succeeded:
                    for placeholder in placeholders {
                        updateGenerationMetadata(placeholder, editor: editor) { input in
                            input.providerJobId = providerJobID
                            input.resultURLs = job.resultURLs.map(\.absoluteString)
                        }
                    }
                    editor.onProjectCheckpointRequired?()
                    await finalizeSuccess(
                        urlStrings: job.resultURLs.map(\.absoluteString),
                        placeholders: placeholders,
                        editor: editor,
                        onComplete: onComplete,
                        onFailure: onFailure
                    )
                    return
                case .failed, .cancelled:
                    await failProviderJob(job, placeholders: placeholders, editor: editor, onFailure: onFailure)
                    return
                case .queued, .running, .downloading, .needsAttention:
                    break
                }
                try await Task.sleep(for: .seconds(2))
            } catch is CancellationError {
                return
            } catch {
                Log.generation.warning("direct provider status check failed; retrying")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func failProviderJob(
        _ job: ProviderGenerationJob,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onFailure: (@MainActor () -> Void)?
    ) async {
        let suffix = job.errorCode.map { " (\($0))" } ?? ""
        let message = job.state == .cancelled ? "Generation cancelled" : "Generation failed\(suffix)"
        for placeholder in placeholders {
            updateGenerationMetadata(placeholder, editor: editor, status: .failed(message)) { input in
                input.providerJobId = job.providerJobID
            }
        }
        editor.onProjectCheckpointRequired?()
        onFailure?()
        if let localJobID = placeholders.first?.generationInput?.localJobId {
            _ = try? await jobStore.transition(
                jobID: localJobID,
                to: job.state == .cancelled ? .cancelled : .failed,
                providerJobID: job.providerJobID,
                errorCode: job.errorCode,
                errorMessage: message
            )
            await cleanupTemporaryReferences(jobID: localJobID)
        }
    }

    private func monitorBackendJob(
        backendJobId: String,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        failIfUnavailable: Bool = false,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        guard let publisher = GenerationBackend.subscribe(jobId: backendJobId) else {
            if failIfUnavailable {
                for placeholder in placeholders {
                    updateGenerationMetadata(placeholder, editor: editor, status: .failed("Backend not configured"))
                }
                editor.onProjectCheckpointRequired?()
                onFailure?()
            }
            return
        }

        for await jobOpt in backendJobStream(from: publisher) {
            guard let job = jobOpt else { continue }
            if await applyBackendJobUpdate(
                job: job,
                backendJobId: backendJobId,
                placeholders: placeholders,
                editor: editor,
                onComplete: onComplete,
                onFailure: onFailure
            ) {
                return
            }
        }

        // Stream ended without a terminal update: finish from persisted URLs, else retry on reopen.
        let persisted = placeholders.compactMap(\.generationInput?.resultURLs).first ?? []
        guard !persisted.isEmpty else { return }
        await finalizeSuccess(
            urlStrings: persisted,
            placeholders: placeholders,
            editor: editor,
            onComplete: onComplete,
            onFailure: onFailure
        )
    }

    private func backendJobStream<Failure: Error>(
        from publisher: AnyPublisher<BackendGenerationJob?, Failure>
    ) -> AsyncStream<BackendGenerationJob?> {
        AsyncStream<BackendGenerationJob?> { continuation in
            let cancellable = publisher
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in continuation.finish() },
                    receiveValue: { value in continuation.yield(value) },
                )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private func applyBackendJobUpdate(
        job: BackendGenerationJob,
        backendJobId: String,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async -> Bool {
        switch job.status {
        case .succeeded:
            if updateBackendJobMetadata(
                placeholders,
                backendJobId: backendJobId,
                editor: editor
            ) {
                editor.onProjectCheckpointRequired?()
            }
            await finalizeSuccess(
                urlStrings: job.resultUrls ?? [],
                placeholders: placeholders,
                editor: editor,
                onComplete: onComplete,
                onFailure: onFailure,
            )
            return true
        case .failed:
            let message = job.errorMessage ?? "Generation failed"
            Log.generation.error("job \(backendJobId) failed: \(message)")
            for placeholder in placeholders {
                updateGenerationMetadata(placeholder, editor: editor, status: .failed(message)) { input in
                    input.backendJobId = backendJobId
                }
            }
            editor.onProjectCheckpointRequired?()
            onFailure?()
            return true
        case .queued, .running:
            if updateBackendJobMetadata(
                placeholders,
                backendJobId: backendJobId,
                editor: editor
            ) {
                editor.onProjectCheckpointRequired?()
            }
            return false
        }
    }

    @discardableResult
    private func updateBackendJobMetadata(
        _ placeholders: [MediaAsset],
        backendJobId: String,
        editor: EditorViewModel
    ) -> Bool {
        var changed = false
        for placeholder in placeholders {
            guard placeholder.generationStatus != .downloading,
                    placeholder.generationStatus != .generating ||
                    placeholder.generationInput?.backendJobId != backendJobId else {
                continue
            }
            updateGenerationMetadata(placeholder, editor: editor, status: .generating) { input in
                input.backendJobId = backendJobId
            }
            changed = true
        }
        return changed
    }

    private func finalizeSuccess(
        urlStrings: [String],
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        let localJobID = placeholders.first?.generationInput?.localJobId
        if let localJobID {
            _ = try? await jobStore.transition(jobID: localJobID, to: .downloading, resultURLs: urlStrings)
        }
        guard !urlStrings.isEmpty else {
            Log.generation.error("backend job succeeded with no resultUrls")
            for placeholder in placeholders {
                updateGenerationMetadata(placeholder, editor: editor, status: .failed("No URL in response"))
            }
            onFailure?()
            if let localJobID {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: .failed,
                    errorCode: "missing_result_url",
                    errorMessage: "Provider succeeded without a result URL"
                )
                await cleanupTemporaryReferences(jobID: localJobID)
            }
            return
        }
        if urlStrings.count < placeholders.count {
            Log.generation.notice("backend returned \(urlStrings.count) URL(s) for \(placeholders.count) placeholder(s); marking extras as failed")
        }

        var finalized: [MediaAsset] = []
        for (i, placeholder) in placeholders.enumerated() {
            let outputIndex = placeholder.generationInput?.outputIndex ?? i
            guard outputIndex < urlStrings.count, let remote = URL(string: urlStrings[outputIndex]) else {
                updateGenerationMetadata(placeholder, editor: editor, status: .failed("No URL for placeholder"))
                continue
            }
            updateGenerationMetadata(placeholder, editor: editor, status: .downloading) { input in
                input.resultURLs = urlStrings
            }
            if await downloadAndFinalize(asset: placeholder, remoteURL: remote, editor: editor) {
                onComplete?(placeholder)
                finalized.append(placeholder)
            }
        }

        if let first = finalized.first {
            if let localJobID {
                _ = try? await jobStore.transition(jobID: localJobID, to: .succeeded, resultURLs: urlStrings)
            }
            AppNotifications.generationComplete(
                assetId: first.id,
                projectURL: editor.projectURL,
                assetName: first.name,
                assetType: first.type,
                count: finalized.count
            )
        } else {
            if let localJobID {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: .failed,
                    errorCode: "finalization_failed",
                    errorMessage: "No generated output could be finalized"
                )
            }
            onFailure?()
        }
        if let localJobID {
            await cleanupTemporaryReferences(jobID: localJobID)
        }
    }

    private func finalizeStagedSuccess(
        relativePaths: [String],
        urlStrings: [String],
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        let localJobID = placeholders.first?.generationInput?.localJobId
        var finalized: [MediaAsset] = []

        for (index, placeholder) in placeholders.enumerated() {
            let outputIndex = placeholder.generationInput?.outputIndex ?? index
            guard outputIndex < relativePaths.count,
                  let stagedURL = GenerationOutputStager.fileURL(
                    relativePath: relativePaths[outputIndex]
                  ),
                  FileManager.default.fileExists(atPath: stagedURL.path)
            else {
                updateGenerationMetadata(
                    placeholder,
                    editor: editor,
                    status: .failed("Recovered output is missing")
                )
                continue
            }

            updateGenerationMetadata(placeholder, editor: editor, status: .downloading) { input in
                input.resultURLs = urlStrings
            }
            let stagedExtension = stagedURL.pathExtension.lowercased()
            if !stagedExtension.isEmpty,
               stagedExtension != placeholder.url.pathExtension.lowercased(),
               ClipType(fileExtension: stagedExtension) != nil {
                placeholder.url = placeholder.url
                    .deletingPathExtension()
                    .appendingPathExtension(stagedExtension)
            }

            do {
                placeholder.url = try await editor.commitStagedProjectMedia(
                    stagedURL,
                    filename: placeholder.url.lastPathComponent
                )
                placeholder.pendingDownloadURL = nil
                editor.importMediaAsset(placeholder, skipAppend: true)
                if await editor.finalizeImportedAsset(placeholder) {
                    editor.appendGenerationLog(for: placeholder)
                    onComplete?(placeholder)
                    finalized.append(placeholder)
                }
            } catch {
                updateGenerationMetadata(
                    placeholder,
                    editor: editor,
                    status: .failed(error.localizedDescription)
                )
            }
        }

        if let first = finalized.first {
            if let localJobID {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: .succeeded,
                    resultURLs: urlStrings
                )
            }
            AppNotifications.generationComplete(
                assetId: first.id,
                projectURL: editor.projectURL,
                assetName: first.name,
                assetType: first.type,
                count: finalized.count
            )
        } else {
            if let localJobID {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: .failed,
                    errorCode: "recovered_finalization_failed",
                    errorMessage: "No staged provider output could be finalized"
                )
            }
            onFailure?()
        }

        if let localJobID {
            await cleanupTemporaryReferences(jobID: localJobID)
        }
    }

    func cancelGeneration(asset: MediaAsset, editor: EditorViewModel) {
        guard let input = asset.generationInput, let localJobID = input.localJobId else { return }
        activeTasks[localJobID]?.cancel()
        Task { @MainActor in
            do {
                let job = try await jobStore.requestCancellation(jobID: localJobID)
                if let providerJobID = job?.providerJobID ?? input.providerJobId {
                    if let provider = try? ProviderModelCatalog.makeProvider(for: input.model) {
                        try? await provider.cancel(jobID: providerJobID)
                    }
                    _ = try await jobStore.transition(jobID: localJobID, to: .cancelled, providerJobID: providerJobID)
                } else {
                    _ = try await jobStore.transition(jobID: localJobID, to: .cancelled)
                }
                await cleanupTemporaryReferences(jobID: localJobID)
                updateGenerationMetadata(asset, editor: editor, status: .failed("Generation cancelled"))
                editor.onProjectCheckpointRequired?()
            } catch {
                _ = try? await jobStore.transition(
                    jobID: localJobID,
                    to: .needsAttention,
                    errorCode: "cancel_request_failed",
                    errorMessage: error.localizedDescription
                )
                updateGenerationMetadata(asset, editor: editor, status: .failed("Cancellation needs attention"))
            }
        }
    }

    private func cleanupTemporaryReferences(jobID: String) async {
        await GenerationReferenceCleanup.run(jobID: jobID, store: jobStore)
        await GenerationOutputStager.cleanup(jobID: jobID)
    }

    private static func providerKind(for type: ClipType) -> ProviderGenerationKind {
        switch type {
        case .image: .image
        case .video, .sequence: .video
        case .audio: .audio
        case .text, .lottie: .image
        }
    }

    private static func localState(for state: ProviderGenerationState) -> GenerationJobState {
        switch state {
        case .queued: .queued
        case .running: .running
        case .downloading: .downloading
        case .succeeded: .downloading
        case .failed: .failed
        case .cancelled: .cancelled
        case .needsAttention: .needsAttention
        }
    }

    private static func requestHash(for input: GenerationInput) -> String {
        let value = [
            input.model,
            input.prompt,
            String(input.duration),
            input.aspectRatio,
            input.resolution ?? "",
            input.quality ?? ""
        ].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

}
