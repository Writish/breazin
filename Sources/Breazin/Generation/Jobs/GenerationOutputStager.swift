import Foundation

enum GenerationOutputStager {
    static let rootDirectory = AppConfiguration.current.applicationSupportDirectory
        .appendingPathComponent("Generation/Outputs", isDirectory: true)

    static func stage(
        jobID: String,
        kind: ProviderGenerationKind,
        resultURLs: [String],
        session: URLSession = .shared,
        root: URL = rootDirectory
    ) async throws -> [String] {
        guard isSafePathComponent(jobID), !resultURLs.isEmpty else {
            throw ProviderGenerationError.invalidResponse
        }
        let directory = root.appendingPathComponent(jobID, isDirectory: true)
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }.value

        var relativePaths: [String] = []
        do {
            for (index, value) in resultURLs.enumerated() {
                try Task.checkCancellation()
                guard let remoteURL = URL(string: value) else {
                    throw ProviderGenerationError.invalidResponse
                }
                let (temporaryURL, response) = try await session.download(from: remoteURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let size = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0
                else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw ProviderGenerationError.invalidResponse
                }
                let fileExtension = outputExtension(
                    remoteURL: remoteURL,
                    response: response,
                    kind: kind
                )
                let filename = "\(index).\(fileExtension)"
                let destination = directory.appendingPathComponent(filename)
                try await Task.detached(priority: .utility) {
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                }.value
                relativePaths.append("\(jobID)/\(filename)")
            }
            return relativePaths
        } catch {
            try? await Task.detached(priority: .utility) {
                try FileManager.default.removeItem(at: directory)
            }.value
            throw error
        }
    }

    static func fileURL(relativePath: String, root: URL = rootDirectory) -> URL? {
        guard !relativePath.hasPrefix("/") else { return nil }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        let candidate = components.reduce(root) { partial, component in
            partial.appendingPathComponent(String(component))
        }.standardizedFileURL
        let normalizedRoot = root.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(normalizedRoot) else { return nil }
        return candidate
    }

    static func cleanup(jobID: String, root: URL = rootDirectory) async {
        guard isSafePathComponent(jobID) else { return }
        let directory = root.appendingPathComponent(jobID, isDirectory: true)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directory)
        }.value
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }

    private static func outputExtension(
        remoteURL: URL,
        response: URLResponse,
        kind: ProviderGenerationKind
    ) -> String {
        let candidates = [
            response.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension },
            remoteURL.pathExtension,
        ].compactMap { $0?.lowercased() }.filter { !$0.isEmpty && $0.count <= 8 }
        if let first = candidates.first { return first }
        if let mime = response.mimeType?.lowercased() {
            switch mime {
            case "image/png": return "png"
            case "image/webp": return "webp"
            case "image/jpeg": return "jpg"
            case "video/mp4": return "mp4"
            case "audio/mp4": return "m4a"
            case "audio/mpeg": return "mp3"
            default: break
            }
        }
        return switch kind {
        case .image: "jpg"
        case .video: "mp4"
        case .audio: "m4a"
        case .upscale: "jpg"
        }
    }
}
