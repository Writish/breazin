import Foundation

struct UploadBrokerReservation: Sendable {
    let uploadID: String
    let uploadHandle: String
    let uploadURL: URL
    let uploadHeaders: [String: String]
    let uploadURLExpiresAt: Date
    let objectExpiresAt: Date
}

struct UploadBrokerAsset: Sendable {
    let uploadID: String
    let assetURL: URL
    let assetURLExpiresAt: Date
    let objectExpiresAt: Date
}

enum UploadBrokerError: LocalizedError {
    case missingCredential
    case invalidResponse
    case remote(code: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredential: "Add the temporary upload Broker token in Settings > Providers."
        case .invalidResponse: "The temporary upload Broker returned an invalid response."
        case .remote(let code, let status): "Temporary upload failed (\(code), HTTP \(status))."
        }
    }
}

protocol UploadBrokerServing: Sendable {
    func reserve(
        jobID: String,
        assetID: String,
        mediaKind: String,
        asset: StandardizedReferenceAsset
    ) async throws -> UploadBrokerReservation
    func upload(fileURL: URL, reservation: UploadBrokerReservation) async throws
    func complete(uploadHandle: String) async throws -> UploadBrokerAsset
    func refresh(uploadHandle: String) async throws -> UploadBrokerAsset
    func delete(uploadHandle: String) async throws
}

actor UploadBrokerClient: UploadBrokerServing {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(
        baseURL: URL = AppConfiguration.current.uploadBrokerBaseURL,
        token: String? = ProviderCredentialStore.loadUploadBrokerToken(),
        session: URLSession = .shared
    ) throws {
        guard let token, !token.isEmpty else { throw UploadBrokerError.missingCredential }
        self.baseURL = baseURL
        self.token = token
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func reserve(
        jobID: String,
        assetID: String,
        mediaKind: String,
        asset: StandardizedReferenceAsset
    ) async throws -> UploadBrokerReservation {
        let body = CreateRequest(
            jobId: jobID,
            assetId: assetID,
            mediaKind: mediaKind,
            contentType: asset.contentType,
            contentLength: asset.contentLength,
            checksumSHA256: asset.checksumSHA256,
            fileExtension: asset.fileURL.pathExtension
        )
        let response: CreateResponse = try await send(path: "/v1/uploads", method: "POST", body: body)
        guard let uploadURL = URL(string: response.uploadURL) else { throw UploadBrokerError.invalidResponse }
        return UploadBrokerReservation(
            uploadID: response.uploadId,
            uploadHandle: response.uploadHandle,
            uploadURL: uploadURL,
            uploadHeaders: response.uploadHeaders,
            uploadURLExpiresAt: response.uploadURLExpiresAt,
            objectExpiresAt: response.objectExpiresAt
        )
    }

    func upload(fileURL: URL, reservation: UploadBrokerReservation) async throws {
        var request = URLRequest(url: reservation.uploadURL)
        request.httpMethod = "PUT"
        for (name, value) in reservation.uploadHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw UploadBrokerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadBrokerError.remote(code: "r2_upload_failed", status: http.statusCode)
        }
    }

    func complete(uploadHandle: String) async throws -> UploadBrokerAsset {
        let response: AssetResponse = try await send(
            path: "/v1/uploads/complete",
            method: "POST",
            body: HandleRequest(uploadHandle: uploadHandle)
        )
        return try asset(response)
    }

    func refresh(uploadHandle: String) async throws -> UploadBrokerAsset {
        let response: AssetResponse = try await send(
            path: "/v1/uploads/refresh",
            method: "POST",
            body: HandleRequest(uploadHandle: uploadHandle)
        )
        return try asset(response)
    }

    func delete(uploadHandle: String) async throws {
        let _: EmptyResponse = try await send(
            path: "/v1/uploads",
            method: "DELETE",
            body: HandleRequest(uploadHandle: uploadHandle),
            acceptsEmptyResponse: true
        )
    }

    private func asset(_ response: AssetResponse) throws -> UploadBrokerAsset {
        guard let url = URL(string: response.assetURL) else { throw UploadBrokerError.invalidResponse }
        return UploadBrokerAsset(
            uploadID: response.uploadId,
            assetURL: url,
            assetURLExpiresAt: response.assetURLExpiresAt,
            objectExpiresAt: response.objectExpiresAt
        )
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        acceptsEmptyResponse: Bool = false
    ) async throws -> ResponseBody {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw UploadBrokerError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = try encoder.encode(body)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UploadBrokerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw UploadBrokerError.remote(code: envelope?.error.code ?? "broker_request_failed", status: http.statusCode)
        }
        if acceptsEmptyResponse && data.isEmpty, let empty = EmptyResponse() as? ResponseBody { return empty }
        do { return try decoder.decode(ResponseBody.self, from: data) }
        catch { throw UploadBrokerError.invalidResponse }
    }
}

private extension UploadBrokerClient {
    struct CreateRequest: Encodable {
        let jobId: String
        let assetId: String
        let mediaKind: String
        let contentType: String
        let contentLength: Int64
        let checksumSHA256: String
        let fileExtension: String
    }
    struct HandleRequest: Encodable { let uploadHandle: String }
    struct CreateResponse: Decodable {
        let uploadId: String
        let uploadHandle: String
        let uploadURL: String
        let uploadHeaders: [String: String]
        let uploadURLExpiresAt: Date
        let objectExpiresAt: Date
    }
    struct AssetResponse: Decodable {
        let uploadId: String
        let assetURL: String
        let assetURLExpiresAt: Date
        let objectExpiresAt: Date
    }
    struct ErrorEnvelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
    struct EmptyResponse: Decodable { init() {} }
}
