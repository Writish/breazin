import AVFoundation
import CryptoKit
import Foundation

struct StandardizedReferenceAsset: Sendable {
    let fileURL: URL
    let relativePath: String
    let contentType: String
    let contentLength: Int64
    let checksumSHA256: String
}

enum ReferenceAssetStandardizer {
    struct StandardizationError: LocalizedError {
        let reason: String
        var errorDescription: String? { "Reference asset standardization failed: \(reason)" }
    }

    static func standardize(
        sourceURL: URL,
        type: ClipType,
        jobID: String,
        uploadID: String,
        rootDirectory: URL = AppConfiguration.current.applicationSupportDirectory
            .appendingPathComponent("Generation/Uploads", isDirectory: true)
    ) async throws -> StandardizedReferenceAsset {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let directory = rootDirectory.appendingPathComponent(jobID, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output: (URL, String)
            switch type {
            case .image:
                output = try standardizeImage(sourceURL, directory: directory, uploadID: uploadID)
            case .video, .sequence:
                output = try await standardizeVideo(sourceURL, directory: directory, uploadID: uploadID)
            case .audio:
                output = try await standardizeAudio(sourceURL, directory: directory, uploadID: uploadID)
            case .text, .lottie:
                throw StandardizationError(reason: "unsupported media kind")
            }
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: output.0.path)
            guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                throw StandardizationError(reason: "empty output")
            }
            let checksum = try checksumSHA256(fileURL: output.0)
            let relative = output.0.path.replacingOccurrences(of: rootDirectory.path + "/", with: "")
            return StandardizedReferenceAsset(
                fileURL: output.0,
                relativePath: relative,
                contentType: output.1,
                contentLength: size,
                checksumSHA256: checksum
            )
        }.value
    }

    private static func standardizeImage(_ sourceURL: URL, directory: URL, uploadID: String) throws -> (URL, String) {
        guard let output = ImageEncoder.encode(url: sourceURL) else {
            throw StandardizationError(reason: "image could not be decoded")
        }
        let normalized: ImageEncoder.Output
        if ["image/jpeg", "image/png", "image/webp"].contains(output.mime) {
            normalized = output
        } else if let image = ImageEncoder.thumbnail(url: sourceURL, maxPixelSize: ImageEncoder.maxLongestEdge),
                  let data = ImageEncoder.encodeJPEG(image, quality: 0.85) {
            normalized = ImageEncoder.Output(data: data, mime: "image/jpeg")
        } else {
            throw StandardizationError(reason: "image format could not be normalized")
        }
        let fileExtension = normalized.mime == "image/png" ? "png" : normalized.mime == "image/webp" ? "webp" : "jpg"
        let destination = directory.appendingPathComponent("\(uploadID).\(fileExtension)")
        try normalized.data.write(to: destination, options: .atomic)
        return (destination, normalized.mime)
    }

    private static func standardizeVideo(_ sourceURL: URL, directory: URL, uploadID: String) async throws -> (URL, String) {
        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw StandardizationError(reason: "video track is missing")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw StandardizationError(reason: "H.264 export is unavailable")
        }
        let destination = directory.appendingPathComponent("\(uploadID).mp4")
        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            session.cancelExport()
            throw CancellationError()
        }
        return (destination, "video/mp4")
    }

    private static func standardizeAudio(_ sourceURL: URL, directory: URL, uploadID: String) async throws -> (URL, String) {
        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw StandardizationError(reason: "audio track is missing")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw StandardizationError(reason: "AAC export is unavailable")
        }
        let destination = directory.appendingPathComponent("\(uploadID).m4a")
        do {
            try await session.export(to: destination, as: .m4a)
        } catch is CancellationError {
            session.cancelExport()
            throw CancellationError()
        }
        return (destination, "audio/mp4")
    }

    private static func checksumSHA256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
