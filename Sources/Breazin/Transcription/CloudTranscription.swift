import Foundation

enum CloudTranscription {
    static func transcribe(
        fileURL: URL,
        range: ClosedRange<Double>?,
        preferredLocale: Locale?
    ) async throws -> TranscriptionResult {
        let language = languageIdentifier(preferredLocale)
        if let cached = await TranscriptCache.shared.cachedCloudTranscript(
            for: fileURL,
            range: range,
            language: language,
            providerID: TranscriptionProviderCatalog.openAI
        ) {
            return cached
        }

        let provider = try TranscriptionProviderCatalog.makeCloudProvider()
        let tempAudioURL = try await Transcription.extractAudioTrack(
            from: fileURL,
            range: range,
            fileExtension: "wav"
        )
        defer { try? FileManager.default.removeItem(at: tempAudioURL) }

        let result = try await provider.transcribe(ProviderTranscriptionRequest(
            fileURL: tempAudioURL,
            preferredLocaleIdentifier: language,
            censorProfanity: false
        ))
            .offsetting(by: range?.lowerBound ?? 0)
        await TranscriptCache.shared.storeCloudTranscript(
            result,
            for: fileURL,
            range: range,
            language: language,
            providerID: provider.id
        )
        return result
    }

    static func languageIdentifier(_ preferredLocale: Locale?) -> String? {
        preferredLocale.flatMap { locale in
            locale.language.languageCode?.identifier ?? locale.identifier(.bcp47)
        }
    }

}
