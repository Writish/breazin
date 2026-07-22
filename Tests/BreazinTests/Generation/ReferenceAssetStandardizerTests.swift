import AVFoundation
import Foundation
import Testing
@testable import Breazin

@Suite("Generation reference standardization", .serialized)
struct ReferenceAssetStandardizerTests {
    @Test func imageBecomesSupportedUploadWithStreamingChecksum() async throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("source.png")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try png.write(to: source)

        let asset = try await ReferenceAssetStandardizer.standardize(
            sourceURL: source,
            type: .image,
            jobID: "job-image",
            uploadID: "upload-image",
            rootDirectory: root
        )

        #expect(["image/png", "image/jpeg"].contains(asset.contentType))
        #expect(asset.contentLength > 0)
        #expect(asset.checksumSHA256.count == 64)
        #expect(!asset.relativePath.hasPrefix("/"))
    }

    @Test func videoIsNormalizedToMP4() async throws {
        let root = temporaryDirectory()
        let source = try await FixtureVideo.write(scenes: [.init(rgb: (240, 20, 20), seconds: 0.4)])
        defer { try? FileManager.default.removeItem(at: source) }

        let asset = try await ReferenceAssetStandardizer.standardize(
            sourceURL: source,
            type: .video,
            jobID: "job-video",
            uploadID: "upload-video",
            rootDirectory: root
        )

        #expect(asset.contentType == "video/mp4")
        #expect(asset.fileURL.pathExtension == "mp4")
        #expect(asset.contentLength > 0)
    }

    @Test func audioIsNormalizedToAACInM4A() async throws {
        let root = temporaryDirectory()
        let source = try writeSilence(to: root.appendingPathComponent("source.wav"))

        let asset = try await ReferenceAssetStandardizer.standardize(
            sourceURL: source,
            type: .audio,
            jobID: "job-audio",
            uploadID: "upload-audio",
            rootDirectory: root
        )

        #expect(asset.contentType == "audio/mp4")
        #expect(asset.fileURL.pathExtension == "m4a")
        #expect(asset.contentLength > 0)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("breazin-reference-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSilence(to url: URL) throws -> URL {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        try file.write(from: buffer)
        return url
    }
}
