import Foundation

struct OpenAITranscriptionProvider: TranscriptionProvider {
    typealias Transport = @Sendable (URLRequest, URL) async throws -> (Data, URLResponse)

    let id = TranscriptionProviderCatalog.openAI

    private let apiKey: String
    private let baseURL: URL
    private let model: String
    private let transport: Transport

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        model: String = TranscriptionProviderCatalog.defaultModel
    ) {
        self.init(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            transport: { request, bodyURL in
                try await session.upload(for: request, fromFile: bodyURL)
            }
        )
    }

    init(
        apiKey: String,
        baseURL: URL,
        model: String,
        transport: @escaping Transport
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.transport = transport
    }

    func transcribe(_ request: ProviderTranscriptionRequest) async throws -> TranscriptionResult {
        guard !request.censorProfanity else {
            throw ProviderTranscriptionError.unsupportedInput(
                "Cloud transcription does not support profanity filtering. Choose Local transcription."
            )
        }
        guard request.fileURL.isFileURL else {
            throw ProviderTranscriptionError.unsupportedInput(
                "Cloud transcription requires a local audio file."
            )
        }

        let boundary = "breazin-\(UUID().uuidString)"
        let bodyURL = try await makeMultipartBody(
            audioURL: request.fileURL,
            boundary: boundary,
            language: normalizedLanguage(request.preferredLocaleIdentifier)
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let endpoint = baseURL.appendingPathComponent("v1/audio/transcriptions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 10 * 60
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport(urlRequest, bodyURL)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderTranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw ProviderTranscriptionError.remote(
                code: envelope?.error.code,
                message: envelope?.error.message
                    ?? "Transcription request failed (HTTP \(http.statusCode))."
            )
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderTranscriptionError.invalidResponse
        }
        if !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           decoded.words.isEmpty {
            throw ProviderTranscriptionError.invalidResponse
        }
        return TranscriptionResult(
            text: decoded.text,
            language: decoded.language,
            words: decoded.words.map {
                TranscriptionWord(text: $0.word, start: $0.start, end: $0.end)
            },
            segments: decoded.segments.map {
                TranscriptionSegment(text: $0.text, start: $0.start, end: $0.end)
            }
        )
    }

    private func makeMultipartBody(
        audioURL: URL,
        boundary: String,
        language: String?
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-transcription-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw ProviderTranscriptionError.unsupportedInput(
                "Could not prepare the transcription upload."
            )
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            try writeField("model", value: model, boundary: boundary, to: output)
            try writeField("response_format", value: "verbose_json", boundary: boundary, to: output)
            try writeField(
                "timestamp_granularities[]",
                value: "word",
                boundary: boundary,
                to: output
            )
            try writeField(
                "timestamp_granularities[]",
                value: "segment",
                boundary: boundary,
                to: output
            )
            if let language {
                try writeField("language", value: language, boundary: boundary, to: output)
            }
            let fileHeader = "--\(boundary)\r\n"
                    + "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
                    + "Content-Type: audio/wav\r\n\r\n"
            try output.write(contentsOf: Data(fileHeader.utf8))

            let input = try FileHandle(forReadingFrom: audioURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func writeField(
        _ name: String,
        value: String,
        boundary: String,
        to output: FileHandle
    ) throws {
        let field = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                + "\(value)\r\n"
        try output.write(contentsOf: Data(field.utf8))
    }

    private func normalizedLanguage(_ identifier: String?) -> String? {
        guard let identifier,
              let code = Locale(identifier: identifier).language.languageCode?.identifier,
              code.range(of: #"^[A-Za-z]{2,3}$"#, options: .regularExpression) != nil
        else { return nil }
        return code.lowercased()
    }
}

private extension OpenAITranscriptionProvider {
    struct Response: Decodable {
        struct Word: Decodable {
            let word: String
            let start: Double
            let end: Double
        }

        struct Segment: Decodable {
            let text: String
            let start: Double
            let end: Double
        }

        let text: String
        let language: String?
        let words: [Word]
        let segments: [Segment]

        private enum CodingKeys: String, CodingKey {
            case text, language, words, segments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            language = try container.decodeIfPresent(String.self, forKey: .language)
            words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
            segments = try container.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        }
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let code: String?
            let message: String
        }

        let error: Detail
    }
}
