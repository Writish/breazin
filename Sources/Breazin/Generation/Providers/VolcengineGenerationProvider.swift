import Foundation

struct VolcengineGenerationProvider: GenerationProvider {
    let id: ProviderID = ProviderModelCatalog.volcengineArk

    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://ark.cn-beijing.volces.com")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    func models() async throws -> [ProviderGenerationModel] {
        [
            .init(id: ProviderModelCatalog.seedream5Pro, displayName: "Doubao Seedream 5.0 Pro", kinds: [.image]),
            .init(id: ProviderModelCatalog.seedance2, displayName: "Doubao Seedance 2.0", kinds: [.video]),
        ]
    }

    func submit(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob {
        switch (request.kind, request.model) {
        case (.image, ProviderModelCatalog.seedream5Pro):
            return try await submitImage(request)
        case (.video, ProviderModelCatalog.seedance2):
            return try await submitVideo(request)
        default:
            throw ProviderGenerationError.unsupportedModel(request.model)
        }
    }

    func status(jobID: String) async throws -> ProviderGenerationJob {
        let data = try await perform(path: "/api/v3/contents/generations/tasks/\(pathComponent(jobID))", method: "GET")
        let response = try decode(VideoTaskResponse.self, from: data)
        return makeVideoJob(response, fallbackID: jobID)
    }

    func cancel(jobID: String) async throws {
        _ = try await perform(path: "/api/v3/contents/generations/tasks/\(pathComponent(jobID))", method: "DELETE")
    }

    private func submitImage(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob {
        let payload = ImageRequest(
            model: request.model,
            prompt: request.prompt,
            image: request.inputs.isEmpty ? nil : request.inputs.map { $0.url.absoluteString },
            size: request.options["size"],
            responseFormat: "url",
            watermark: request.options["watermark"] == "true"
        )
        let body = try JSONEncoder().encode(payload)
        let data = try await perform(path: "/api/v3/images/generations", method: "POST", body: body)
        let response = try decode(ImageResponse.self, from: data)
        let urls = response.data.compactMap(\.url).compactMap(URL.init(string:))
        guard !urls.isEmpty else { throw ProviderGenerationError.invalidResponse }
        return ProviderGenerationJob(
            providerID: id,
            providerJobID: "image-\(request.idempotencyKey)",
            state: .succeeded,
            resultURLs: urls,
            errorCode: nil
        )
    }

    private func submitVideo(_ request: ProviderGenerationRequest) async throws -> ProviderGenerationJob {
        let content = [VideoContent(type: "text", text: request.prompt)] + request.inputs.map { input in
            switch input.contentType.split(separator: "/").first {
            case "video": VideoContent(type: "video_url", url: input.url.absoluteString, role: input.role)
            case "audio": VideoContent(type: "audio_url", url: input.url.absoluteString, role: input.role)
            default: VideoContent(type: "image_url", url: input.url.absoluteString, role: input.role)
            }
        }
        let payload = VideoRequest(
            model: request.model,
            content: content,
            duration: request.options["duration"].flatMap(Int.init),
            ratio: request.options["ratio"],
            resolution: request.options["resolution"],
            generateAudio: request.options["generateAudio"].map { $0 == "true" } ?? true,
            watermark: request.options["watermark"] == "true"
        )
        let body = try JSONEncoder().encode(payload)
        let data = try await perform(path: "/api/v3/contents/generations/tasks", method: "POST", body: body)
        let response = try decode(VideoTaskResponse.self, from: data)
        guard let jobID = response.id, !jobID.isEmpty else { throw ProviderGenerationError.invalidResponse }
        return makeVideoJob(response, fallbackID: jobID)
    }

    private func makeVideoJob(_ response: VideoTaskResponse, fallbackID: String) -> ProviderGenerationJob {
        let state: ProviderGenerationState = switch response.status {
        case "queued": .queued
        case "running": .running
        case "succeeded": .succeeded
        case "failed", "expired": .failed
        case "cancelled": .cancelled
        default: .needsAttention
        }
        return ProviderGenerationJob(
            providerID: id,
            providerJobID: response.id ?? fallbackID,
            state: state,
            resultURLs: [response.content?.videoURL].compactMap { $0 }.compactMap(URL.init(string:)),
            errorCode: response.error?.code
        )
    }

    private func perform(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ProviderGenerationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderGenerationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let detail = payload?.error ?? payload?.topLevelError
            throw ProviderGenerationError.remote(
                code: detail?.code,
                message: detail?.message ?? "Volcengine request failed (HTTP \(http.statusCode))."
            )
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ProviderGenerationError.invalidResponse }
    }

    private func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private extension VolcengineGenerationProvider {
    struct ImageRequest: Encodable {
        let model: String
        let prompt: String
        let image: [String]?
        let size: String?
        let responseFormat: String
        let watermark: Bool

        enum CodingKeys: String, CodingKey {
            case model, prompt, image, size, watermark
            case responseFormat = "response_format"
        }
    }

    struct ImageResponse: Decodable {
        struct Item: Decodable { let url: String? }
        let data: [Item]
    }

    struct VideoRequest: Encodable {
        let model: String
        let content: [VideoContent]
        let duration: Int?
        let ratio: String?
        let resolution: String?
        let generateAudio: Bool
        let watermark: Bool

        enum CodingKeys: String, CodingKey {
            case model, content, duration, ratio, resolution, watermark
            case generateAudio = "generate_audio"
        }
    }

    struct VideoContent: Encodable {
        let type: String
        let text: String?
        let url: String?
        let role: String?

        init(type: String, text: String) {
            self.type = type; self.text = text; self.url = nil; self.role = nil
        }

        init(type: String, url: String, role: String?) {
            self.type = type; self.text = nil; self.url = url; self.role = role
        }

        enum CodingKeys: String, CodingKey {
            case type, text, role
            case imageURL = "image_url"
            case videoURL = "video_url"
            case audioURL = "audio_url"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encodeIfPresent(text, forKey: .text)
            try c.encodeIfPresent(role, forKey: .role)
            guard let url else { return }
            struct URLValue: Encodable { let url: String }
            switch type {
            case "video_url": try c.encode(URLValue(url: url), forKey: .videoURL)
            case "audio_url": try c.encode(URLValue(url: url), forKey: .audioURL)
            default: try c.encode(URLValue(url: url), forKey: .imageURL)
            }
        }
    }

    struct VideoTaskResponse: Decodable {
        struct Content: Decodable {
            let videoURL: String?
            enum CodingKeys: String, CodingKey { case videoURL = "video_url" }
        }
        struct Detail: Decodable { let code: String?; let message: String? }
        let id: String?
        let status: String?
        let content: Content?
        let error: Detail?
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let code: String?; let message: String? }
        let error: Detail?
        let code: String?
        let message: String?
        var topLevelError: Detail? {
            guard code != nil || message != nil else { return nil }
            return Detail(code: code, message: message)
        }
    }
}
