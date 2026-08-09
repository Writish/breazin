import Foundation

extension ToolExecutor {
    private func requireGenerationAccess(for modelId: String) throws {
        guard let providerID = ProviderModelCatalog.providerID(for: modelId) else {
            throw ToolError("Model '\(modelId)' has no installed provider adapter.")
        }
        guard ProviderCredentialStore.loadAPIKey(for: providerID) != nil else {
            throw ToolError("Add the Volcengine API key in Settings > Providers, then retry.")
        }
    }

    private func defaultModelId(_ ids: [String], kind: String) throws -> String {
        guard !ids.isEmpty else {
            throw ToolError("Model catalog not loaded yet. Try again in a moment.")
        }
        return ids[0]
    }

    func generate(_ editor: EditorViewModel, _ args: [String: Any], type: ClipType) throws -> ToolResult {
        let prompt = try args.requireString("prompt")
        switch type {
        case .sequence:
            throw ToolError("Cannot generate a sequence. Sequences are timelines.")
        case .video:
            let modelId = try args.string("model") ?? defaultModelId(
                VideoModelConfig.allModels.map(\.id), kind: "video")
            guard let model = VideoModelConfig.allModels.first(where: { $0.id == modelId }) else {
                throw ToolError("Unknown model '\(modelId)'. Available: \(VideoModelConfig.allModels.map(\.id).joined(separator: ", "))")
            }
            try requireGenerationAccess(for: model.id)
            return model.requiresSourceVideo
                ? try generateVideoEdit(editor, args, prompt: prompt, model: model)
                : try generateVideoText(editor, args, prompt: prompt, model: model)
        case .image:
            return try generateImage(editor, args, prompt: prompt)
        case .audio:
            throw ToolError("internal: audio generation is dispatched via the async path")
        case .text:
            throw ToolError("Text generation is not wired through the generate tool.")
        case .lottie:
            throw ToolError("Lottie animations aren't generated through this tool.")
        }
    }

    private func generateVideoEdit(
        _ editor: EditorViewModel, _ args: [String: Any],
        prompt: String, model: VideoModelConfig
    ) throws -> ToolResult {
        guard let sourceRef = args.string("sourceVideoMediaRef") else {
            throw ToolError("Model '\(model.id)' requires 'sourceVideoMediaRef' pointing to a video asset.")
        }
        let sourceAsset = try asset(sourceRef, editor: editor, label: "Source video")
        let trimmed = try trimmedSource(args, editor: editor, source: sourceAsset)

        var imageRefs: [MediaAsset] = []
        for id in args.stringArray("referenceImageMediaRefs") {
            imageRefs.append(try asset(id, editor: editor, label: "Reference image"))
        }

        if let err = model.validate(duration: 0, aspectRatio: "", resolution: nil) {
            throw ToolError(err)
        }
        let inputAssets = VideoGenerationSubmission.InputAssets(sourceVideo: sourceAsset, imageRefs: imageRefs)
        if let err = inputAssets.validate(for: model) {
            throw ToolError(err)
        }

        let genInput = GenerationInput(
            prompt: prompt, model: model.id, duration: Int(sourceAsset.duration.rounded()),
            aspectRatio: "", resolution: nil
        )
        let placeholderId = VideoGenerationSubmission.make(
            genInput: genInput,
            model: model,
            inputAssets: inputAssets,
            placeholderDuration: trimmed?.durationSeconds ?? (sourceAsset.duration > 0 ? sourceAsset.duration : 5),
            trimmedSourceOverride: trimmed,
            name: args.string("name"),
            folderId: sourceAsset.folderId,
            generateAudio: true
        ).submit(
            service: editor.generationService,
            projectURL: editor.projectURL,
            editor: editor
        )
        return generationStartedResult(
            "Edit started. Placeholder asset ID: \(placeholderId). Model: \(model.displayName), source: \(sourceAsset.name)",
            placeholderID: placeholderId,
            editor: editor
        )
    }

    private func generateVideoText(
        _ editor: EditorViewModel, _ args: [String: Any],
        prompt: String, model: VideoModelConfig
    ) throws -> ToolResult {
        guard !prompt.isEmpty else { throw ToolError("Empty prompt") }

        let duration = args.int("duration") ?? model.durations.first ?? 0
        let aspectRatio = args.string("aspectRatio") ?? model.aspectRatios.first ?? ""
        let resolution = args.string("resolution") ?? model.resolutions?.first

        if let err = model.validate(duration: duration, aspectRatio: aspectRatio, resolution: resolution) {
            throw ToolError(err)
        }

        var frameSlots: [MediaAsset] = []
        if let startRef = args.string("startFrameMediaRef") {
            frameSlots.append(try asset(startRef, editor: editor, label: "Start frame"))
        }
        if let endRef = args.string("endFrameMediaRef") {
            frameSlots.append(try asset(endRef, editor: editor, label: "End frame"))
        }

        func refs(_ argName: String, label: String) throws -> [MediaAsset] {
            try args.stringArray(argName).map { id in
                try asset(id, editor: editor, label: label)
            }
        }
        let imageRefs = try refs("referenceImageMediaRefs", label: "Image reference")
        let videoRefs = try refs("referenceVideoMediaRefs", label: "Video reference")
        let audioRefs = try refs("referenceAudioMediaRefs", label: "Audio reference")
        let inputAssets = VideoGenerationSubmission.InputAssets(
            frames: frameSlots,
            imageRefs: imageRefs,
            videoRefs: videoRefs,
            audioRefs: audioRefs
        )
        if let err = inputAssets.validate(for: model) {
            throw ToolError(err)
        }

        let imageRefCount = imageRefs.count
        let videoRefCount = videoRefs.count
        let audioRefCount = audioRefs.count
        let totalRefs = inputAssets.totalRefCount

        let genInput = GenerationInput(
            prompt: prompt, model: model.id, duration: duration,
            aspectRatio: aspectRatio, resolution: resolution
        )

        let folderId = try resolveFolder(
            args, editor: editor, fallbackReferences: inputAssets.textToVideoReferences
        )
        let placeholderId = VideoGenerationSubmission.make(
            genInput: genInput,
            model: model,
            inputAssets: inputAssets,
            placeholderDuration: Double(max(1, duration)),
            name: args.string("name"),
            folderId: folderId,
            generateAudio: true
        ).submit(
            service: editor.generationService,
            projectURL: editor.projectURL,
            editor: editor
        )
        let refSummary = totalRefs > 0
            ? ", refs: \(imageRefCount)img/\(videoRefCount)vid/\(audioRefCount)aud"
            : ""
        return generationStartedResult(
            "Generation started. Placeholder asset ID: \(placeholderId). Model: \(model.displayName), duration: \(duration)s, aspect: \(aspectRatio)\(refSummary)",
            placeholderID: placeholderId,
            editor: editor
        )
    }

    private func generateImage(
        _ editor: EditorViewModel, _ args: [String: Any], prompt: String
    ) throws -> ToolResult {
        guard !prompt.isEmpty else { throw ToolError("Empty prompt") }
        let modelId = try args.string("model") ?? defaultModelId(
            ImageModelConfig.allModels.map(\.id), kind: "image")
        guard let model = ImageModelConfig.allModels.first(where: { $0.id == modelId }) else {
            throw ToolError("Unknown model '\(modelId)'. Available: \(ImageModelConfig.allModels.map(\.id).joined(separator: ", "))")
        }
        try requireGenerationAccess(for: model.id)
        let aspectRatio = args.string("aspectRatio") ?? model.aspectRatios.first ?? ""
        let resolution = args.string("resolution") ?? model.resolutions?.first
        let quality = args.string("quality") ?? model.qualities?.last
        let refIds = args.stringArray("referenceMediaRefs")
        if let err = model.validate(
            aspectRatio: aspectRatio, resolution: resolution, quality: quality,
            imageRefCount: refIds.count, numImages: 1
        ) {
            throw ToolError(err)
        }
        let refs: [MediaAsset] = try refIds.map { id in
            let a = try asset(id, editor: editor, label: "Reference image")
            guard a.type == .image else {
                throw ToolError("referenceMediaRefs entry '\(id)' must be an image asset (got \(a.type.rawValue))")
            }
            return a
        }

        let genInput = GenerationInput(
            prompt: prompt, model: modelId, duration: 0,
            aspectRatio: aspectRatio, resolution: resolution, quality: quality
        )
        let folderId = try resolveFolder(args, editor: editor, fallbackReferences: refs)
        let placeholderId = ImageGenerationSubmission.make(
            genInput: genInput,
            model: model,
            references: refs,
            name: args.string("name"),
            folderId: folderId
        ).submit(
            service: editor.generationService,
            projectURL: editor.projectURL,
            editor: editor
        )
        return generationStartedResult(
            "Generation started. Placeholder asset ID: \(placeholderId). Model: \(model.displayName), aspect: \(aspectRatio)",
            placeholderID: placeholderId,
            editor: editor
        )
    }

    private func generationStartedResult(
        _ message: String,
        placeholderID: String,
        editor: EditorViewModel
    ) -> ToolResult {
        guard let jobID = editor.mediaAssets.first(where: { $0.id == placeholderID })?
            .generationInput?.localJobId else {
            return .ok(message)
        }
        return ToolResult(
            content: [.text(message), .generationJob(id: jobID)],
            isError: false
        )
    }

    private func trimmedSource(
        _ args: [String: Any], editor: EditorViewModel, source: MediaAsset
    ) throws -> TrimmedSource? {
        guard let clipId = args.string("sourceClipId") else { return nil }
        guard let clip = editor.clipFor(id: clipId) else {
            throw ToolError("sourceClipId not found: \(clipId)")
        }
        guard clip.mediaRef == source.id else {
            throw ToolError("sourceClipId \(clipId) references a different asset than the source")
        }
        guard source.type == .video else {
            throw ToolError("sourceClipId only applies to video sources")
        }
        guard clip.trimStartFrame > 0 || clip.trimEndFrame > 0 else { return nil }
        return TrimmedSource(
            sourceURL: source.url,
            trimStartFrame: clip.trimStartFrame,
            trimEndFrame: clip.trimEndFrame,
            sourceFramesConsumed: clip.sourceFramesConsumed,
            fps: editor.timeline.fps
        )
    }

    func listModels(_ args: [String: Any]) -> ToolResult {
        let filter = args.string("type")
        var out: [[String: Any]] = []
        if filter == nil || filter == "video" {
            out += VideoModelConfig.allModels
                .map { Self.videoModelInfo($0, includeType: true) }
        }
        if filter == nil || filter == "image" {
            out += ImageModelConfig.allModels
                .map { Self.imageModelInfo($0, includeType: true) }
        }
        let body: [String: Any] = [
            "models": out,
            "loaded": ModelCatalog.shared.isLoaded,
        ]
        guard let json = Self.jsonString(roundJSONFloatingPointNumbers(body, toPlaces: 3)) else {
            return .error("Failed to encode model list")
        }
        return .ok(json)
    }

    nonisolated static func videoModelInfo(_ m: VideoModelConfig, includeType: Bool = false) -> [String: Any] {
        var info: [String: Any] = [
            "id": m.id, "displayName": m.displayName,
            "durations": m.durations, "aspectRatios": m.aspectRatios,
            "supportsFirstFrame": m.supportsFirstFrame,
            "supportsLastFrame": m.supportsLastFrame,
            "supportsReferences": m.supportsReferences,
        ]
        if includeType { info["type"] = "video" }
        if let r = m.resolutions { info["resolutions"] = r }
        if m.supportsReferences {
            if m.maxReferenceImages > 0 { info["maxReferenceImages"] = m.maxReferenceImages }
            if m.maxReferenceVideos > 0 { info["maxReferenceVideos"] = m.maxReferenceVideos }
            if m.maxReferenceAudios > 0 { info["maxReferenceAudios"] = m.maxReferenceAudios }
            if let total = m.maxTotalReferences { info["maxTotalReferences"] = total }
            if let s = m.maxCombinedVideoRefSeconds { info["maxCombinedVideoRefSeconds"] = Int(s) }
            if let s = m.maxCombinedAudioRefSeconds { info["maxCombinedAudioRefSeconds"] = Int(s) }
            if m.framesAndReferencesExclusive { info["framesAndReferencesExclusive"] = true }
            info["referenceTagNoun"] = m.referenceTagNoun
        }
        return info
    }

    nonisolated static func imageModelInfo(_ m: ImageModelConfig, includeType: Bool = false) -> [String: Any] {
        var info: [String: Any] = [
            "id": m.id, "displayName": m.displayName,
            "aspectRatios": m.aspectRatios,
            "supportsImageReference": m.supportsImageReference,
        ]
        if includeType { info["type"] = "image" }
        if let r = m.resolutions { info["resolutions"] = r }
        if let q = m.qualities { info["qualities"] = q }
        return info
    }

}
