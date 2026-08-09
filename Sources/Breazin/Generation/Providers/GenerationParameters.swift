import Foundation

/// Provider-neutral generation payload used by the UI, Agent tools, and adapters.
enum GenerationParameters: Encodable, Sendable {
    case video(VideoGenerationParams)
    case image(ImageGenerationParams)
    case audio(AudioGenerationParams)
    case upscale(UpscaleGenerationParams)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .video(let params):
            try container.encode(params)
        case .image(let params):
            try container.encode(params)
        case .audio(let params):
            try container.encode(params)
        case .upscale(let params):
            try container.encode(params)
        }
    }
}
