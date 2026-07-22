import Foundation

enum ProviderRequestBuilder {
    static func make(
        model: String,
        params: BackendGenerationParams,
        idempotencyKey: String
    ) throws -> ProviderGenerationRequest {
        switch params {
        case .image(let image):
            return ProviderGenerationRequest(
                idempotencyKey: idempotencyKey,
                kind: .image,
                model: model,
                prompt: image.prompt,
                inputs: try image.imageURLs.map { try asset($0, role: nil) },
                options: [
                    "size": image.resolution ?? "2K",
                    "watermark": "false",
                ]
            )
        case .video(let video):
            var inputs: [ProviderAssetInput] = []
            if let value = video.sourceVideoURL { inputs.append(try asset(value, role: "reference_video")) }
            if let value = video.startFrameURL { inputs.append(try asset(value, role: "first_frame")) }
            if let value = video.endFrameURL { inputs.append(try asset(value, role: "last_frame")) }
            inputs += try video.referenceImageURLs.map { try asset($0, role: "reference_image") }
            inputs += try video.referenceVideoURLs.map { try asset($0, role: "reference_video") }
            inputs += try video.referenceAudioURLs.map { try asset($0, role: "reference_audio") }
            return ProviderGenerationRequest(
                idempotencyKey: idempotencyKey,
                kind: .video,
                model: model,
                prompt: video.prompt,
                inputs: inputs,
                options: [
                    "duration": String(video.duration),
                    "ratio": video.aspectRatio,
                    "resolution": video.resolution ?? "720p",
                    "generateAudio": String(video.generateAudio),
                    "watermark": "false",
                ]
            )
        default:
            throw ProviderGenerationError.unsupportedModel(model)
        }
    }

    private static func asset(_ value: String, role: String?) throws -> ProviderAssetInput {
        guard let url = URL(string: value) else {
            throw ProviderGenerationError.unsupportedInput("A reference asset URL is invalid.")
        }
        return ProviderAssetInput(url: url, contentType: contentType(for: value), role: role)
    }

    private static func contentType(for value: String) -> String {
        if value.hasPrefix("data:") {
            return String(value.dropFirst(5).prefix { $0 != ";" && $0 != "," })
        }
        return switch URL(string: value)?.pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "m4a": "audio/mp4"
        case "png": "image/png"
        case "webp": "image/webp"
        default: "image/jpeg"
        }
    }
}
