import Foundation
import Testing
@testable import Breazin

@Suite("Project document IO")
@MainActor
struct ProjectDocumentIOTests {
    private let fm = FileManager.default

    @Test func directWritePreservesExistingPackageMediaAndThumbnail() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("pp-doc-io-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Project.breazin", isDirectory: true)
        try makePackage(at: package)
        defer { try? fm.removeItem(at: root) }

        let doc = configuredDocument(fileURL: package)
        try doc.write(to: package, ofType: VideoProject.typeIdentifier)

        #expect(try String(contentsOf: package.appendingPathComponent("media/clip.mp4"), encoding: .utf8) == "MEDIA")
        #expect(try String(contentsOf: package.appendingPathComponent(Project.thumbnailFilename), encoding: .utf8) == "THUMB")
        #expect(fm.fileExists(atPath: package.appendingPathComponent(ChatSessionStore.dirName).path))
    }

    @Test func directWriteCopiesPackageMediaAndThumbnailToNewDestination() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("pp-doc-io-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source.breazin", isDirectory: true)
        let destination = root.appendingPathComponent("Destination.breazin", isDirectory: true)
        try makePackage(at: source)
        defer { try? fm.removeItem(at: root) }

        let doc = configuredDocument(fileURL: source)
        try doc.write(to: destination, ofType: VideoProject.typeIdentifier)

        #expect(try String(contentsOf: destination.appendingPathComponent("media/clip.mp4"), encoding: .utf8) == "MEDIA")
        #expect(try String(contentsOf: destination.appendingPathComponent(Project.thumbnailFilename), encoding: .utf8) == "THUMB")
        #expect(fm.fileExists(atPath: destination.appendingPathComponent(Project.timelineFilename).path))
        #expect(fm.fileExists(atPath: destination.appendingPathComponent(Project.manifestFilename).path))
    }

    @Test func legacyPackageIsBackedUpOnceBeforeFirstInPlaceWrite() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("pp-doc-migration-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Legacy.breazin", isDirectory: true)
        try makePackage(at: package)
        defer { try? fm.removeItem(at: root) }

        let legacy = try JSONEncoder().encode(Fixtures.timeline())
        try legacy.write(to: package.appendingPathComponent(Project.timelineFilename))
        let doc = VideoProject()
        doc.fileURL = package
        doc.fileType = VideoProject.typeIdentifier
        try doc.read(from: package, ofType: VideoProject.typeIdentifier)

        try doc.write(to: package, ofType: VideoProject.typeIdentifier)
        let backup = VideoProject.migrationBackupURL(for: package)
        #expect(fm.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: backup.appendingPathComponent(Project.timelineFilename)) == legacy)

        try doc.write(to: package, ofType: VideoProject.typeIdentifier)
        #expect(try Data(contentsOf: backup.appendingPathComponent(Project.timelineFilename)) == legacy)
    }

    @Test func upstreamV0613GoldenMigratesOnceWithoutSemanticLoss() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "palmier-v0.6.13-minimal",
            withExtension: "palmier",
            subdirectory: "Fixtures/Projects"
        ))
        let root = fm.temporaryDirectory.appendingPathComponent(
            "breazin-v0613-migration-\(UUID().uuidString)",
            isDirectory: true
        )
        let package = root.appendingPathComponent("Legacy.palmier", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: fixture, to: package)
        defer { try? fm.removeItem(at: root) }

        let legacyTimeline = try Data(contentsOf: package.appendingPathComponent(Project.timelineFilename))
        let initial = try VideoProject.readProjectPackage(at: package)
        let initialTimeline = try #require(initial.projectFile.timelines.first)
        let initialTrack = try #require(initialTimeline.tracks.first)
        let initialClip = try #require(initialTrack.clips.first)
        let initialEntry = try #require(initial.manifest?.entries.first)

        #expect(initial.requiresMigrationBackup)
        #expect(initialTimeline.id == "legacy-timeline-1")
        #expect(initialTimeline.name == "Legacy Golden")
        #expect(initialTimeline.fps == 24)
        #expect(initialTimeline.width == 1280)
        #expect(initialTimeline.height == 720)
        #expect(initialTrack.id == "legacy-track-1")
        #expect(initialClip.id == "legacy-clip-1")
        #expect(initialClip.mediaRef == initialEntry.id)
        #expect(initialClip.startFrame == 12)
        #expect(initialClip.durationFrames == 90)
        #expect(initialEntry.source == .project(relativePath: "media/missing-reference.mp4"))
        #expect(!fm.fileExists(atPath: package.appendingPathComponent("media/missing-reference.mp4").path))

        let document = VideoProject()
        document.fileURL = package
        document.fileType = VideoProject.typeIdentifier
        try document.read(from: package, ofType: VideoProject.typeIdentifier)
        document.editorViewModel.applyProjectFile(initial.projectFile)
        document.editorViewModel.mediaManifest = try #require(initial.manifest)
        try document.write(to: package, ofType: VideoProject.typeIdentifier)

        let backup = VideoProject.migrationBackupURL(for: package)
        #expect(fm.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: backup.appendingPathComponent(Project.timelineFilename)) == legacyTimeline)
        let migrated = try VideoProject.readProjectPackage(at: package)
        let migratedTimeline = try #require(migrated.projectFile.timelines.first)
        let migratedClip = try #require(migratedTimeline.tracks.first?.clips.first)
        let migratedEntry = try #require(migrated.manifest?.entries.first)
        #expect(!migrated.requiresMigrationBackup)
        #expect(migrated.projectFile.schemaVersion == ProjectFile.currentSchemaVersion)
        #expect(migrated.manifest?.version == MediaManifest.currentSchemaVersion)
        #expect(migratedTimeline.id == initialTimeline.id)
        #expect(migratedTimeline.name == initialTimeline.name)
        #expect(migratedTimeline.tracks.first?.id == initialTrack.id)
        #expect(migratedClip.id == initialClip.id)
        #expect(migratedClip.mediaRef == initialClip.mediaRef)
        #expect(migratedClip.startFrame == initialClip.startFrame)
        #expect(migratedClip.durationFrames == initialClip.durationFrames)
        #expect(migratedEntry == initialEntry)

        let backupTimeline = try Data(contentsOf: backup.appendingPathComponent(Project.timelineFilename))
        try document.write(to: package, ofType: VideoProject.typeIdentifier)
        #expect(try Data(contentsOf: backup.appendingPathComponent(Project.timelineFilename)) == backupTimeline)
        let reopened = try VideoProject.readProjectPackage(at: package)
        #expect(reopened.projectFile.timelines.first == migratedTimeline)
        #expect(reopened.manifest?.entries.first == initialEntry)
    }

    @Test(arguments: [
        CocoaError.Code.fileWriteUnknown,
        CocoaError.Code.fileWriteOutOfSpace,
    ])
    func interruptedOrOutOfSpaceSafeReplaceKeepsOriginalPackage(errorCode: CocoaError.Code) throws {
        let root = fm.temporaryDirectory.appendingPathComponent(
            "breazin-doc-safe-replace-\(UUID().uuidString)",
            isDirectory: true
        )
        let package = root.appendingPathComponent("Project.breazin", isDirectory: true)
        try makePackage(at: package)
        defer { try? fm.removeItem(at: root) }

        let originalTimeline = Data("ORIGINAL-TIMELINE".utf8)
        try originalTimeline.write(to: package.appendingPathComponent(Project.timelineFilename))
        let snapshot = ProjectPackageSnapshot(
            timeline: Data("NEW-TIMELINE".utf8),
            manifest: nil,
            generationLog: nil,
            thumbnail: nil,
            chatSessionFiles: []
        )

        #expect(throws: CocoaError.self) {
            try VideoProject.writeProjectPackage(
                snapshot,
                to: package,
                sourceURL: package,
                beforeSafeReplace: { throw CocoaError(errorCode) }
            )
        }

        #expect(try Data(contentsOf: package.appendingPathComponent(Project.timelineFilename)) == originalTimeline)
        #expect(try String(
            contentsOf: package.appendingPathComponent("media/clip.mp4"),
            encoding: .utf8
        ) == "MEDIA")
        let stagingNames = try fm.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".write-") }
        #expect(stagingNames.isEmpty)
    }

    private func makePackage(at url: URL) throws {
        let media = url.appendingPathComponent(Project.mediaDirectoryName, isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("MEDIA".utf8).write(to: media.appendingPathComponent("clip.mp4"))
        try Data("THUMB".utf8).write(to: url.appendingPathComponent(Project.thumbnailFilename))
    }

    private func configuredDocument(fileURL: URL) -> VideoProject {
        let doc = VideoProject()
        doc.fileURL = fileURL
        doc.fileType = VideoProject.typeIdentifier
        doc.editorViewModel.timeline = Fixtures.timeline()
        var manifest = MediaManifest()
        manifest.entries = [
            MediaManifestEntry(
                id: "clip",
                name: "Clip",
                type: .video,
                source: .project(relativePath: "media/clip.mp4"),
                duration: 1
            )
        ]
        doc.editorViewModel.mediaManifest = manifest
        return doc
    }
}
