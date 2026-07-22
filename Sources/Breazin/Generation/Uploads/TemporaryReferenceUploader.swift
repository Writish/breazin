import Foundation

actor TemporaryReferenceUploader {
    private let store: GenerationJobStore
    private let client: UploadBrokerClient

    init(store: GenerationJobStore = .shared, client: UploadBrokerClient) {
        self.store = store
        self.client = client
    }

    func upload(
        jobID: String,
        ordinal: Int,
        sourceAssetID: String,
        sourceURL: URL,
        type: ClipType
    ) async throws -> UploadBrokerAsset {
        let localUploadID = UUID().uuidString.lowercased()
        let kind = mediaKind(type)
        try await store.createUpload(
            id: localUploadID,
            jobID: jobID,
            ordinal: ordinal,
            sourceAssetID: sourceAssetID,
            mediaKind: kind
        )
        do {
            let standardized = try await ReferenceAssetStandardizer.standardize(
                sourceURL: sourceURL,
                type: type,
                jobID: jobID,
                uploadID: localUploadID
            )
            try await store.recordStandardizedUpload(
                id: localUploadID,
                relativePath: standardized.relativePath,
                contentType: standardized.contentType,
                contentLength: standardized.contentLength,
                checksumSHA256: standardized.checksumSHA256
            )
            try Task.checkCancellation()
            let reservation = try await client.reserve(
                jobID: jobID,
                assetID: sourceAssetID,
                mediaKind: kind,
                asset: standardized
            )
            try await store.recordUploadHandle(
                id: localUploadID,
                uploadID: reservation.uploadID,
                uploadHandle: reservation.uploadHandle
            )
            try Task.checkCancellation()
            try await client.upload(fileURL: standardized.fileURL, reservation: reservation)
            try Task.checkCancellation()
            let asset = try await client.complete(uploadHandle: reservation.uploadHandle)
            try await store.recordUploaded(
                id: localUploadID,
                remoteURL: asset.assetURL.absoluteString,
                remoteURLExpiresAt: asset.assetURLExpiresAt,
                objectExpiresAt: asset.objectExpiresAt
            )
            await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: standardized.fileURL)
            }.value
            return asset
        } catch {
            try? await store.recordUploadFailure(id: localUploadID, code: errorCode(error))
            throw error
        }
    }

    func cleanup(jobID: String) async {
        guard let uploads = try? await store.uploads(jobID: jobID) else { return }
        for upload in uploads {
            guard let handle = upload.uploadHandle else { continue }
            do {
                try await client.delete(uploadHandle: handle)
                try await store.recordUploadDeleted(id: upload.id)
            } catch {
                continue
            }
        }
    }

    func freshAssetURLs(jobID: String, minimumLifetime: TimeInterval = 15 * 60) async throws -> [String] {
        let uploads = try await store.uploads(jobID: jobID)
        var urls: [String] = []
        urls.reserveCapacity(uploads.count)
        for upload in uploads {
            guard upload.state == .uploaded else { throw UploadBrokerError.invalidResponse }
            if let expiry = upload.remoteURLExpiresAt,
               expiry > Date().addingTimeInterval(minimumLifetime),
               let remoteURL = upload.remoteURL {
                urls.append(remoteURL)
                continue
            }
            guard let handle = upload.uploadHandle else { throw UploadBrokerError.invalidResponse }
            let refreshed = try await client.refresh(uploadHandle: handle)
            try await store.recordUploaded(
                id: upload.id,
                remoteURL: refreshed.assetURL.absoluteString,
                remoteURLExpiresAt: refreshed.assetURLExpiresAt,
                objectExpiresAt: refreshed.objectExpiresAt
            )
            urls.append(refreshed.assetURL.absoluteString)
        }
        return urls
    }

    private func mediaKind(_ type: ClipType) -> String {
        switch type {
        case .image: "image"
        case .video, .sequence: "video"
        case .audio: "audio"
        case .text, .lottie: "unsupported"
        }
    }

    private func errorCode(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let error = error as? UploadBrokerError {
            switch error {
            case .missingCredential: return "missing_broker_credential"
            case .invalidResponse: return "invalid_broker_response"
            case .remote(let code, _): return code
            }
        }
        return "reference_upload_failed"
    }
}
