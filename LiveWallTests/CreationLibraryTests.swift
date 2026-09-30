import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import LiveWall

struct CreationLibraryTests {
    @Test func addMovesFilesIntoTheLibraryAndDeleteRemovesThem() async throws {
        let container = try ModelContainer(for: Creation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let library = CreationLibrary(context: container.mainContext)
        let source = try await SyntheticVideo.make(size: CGSize(width: 720, height: 1280), seconds: 3)
        let built = try await LivePhotoBuilder.build(
            LivePhotoRequest(
                sourceURL: source,
                timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)),
                cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                keyFrameOffset: CMTime(seconds: 1, preferredTimescale: 600)
            ),
            in: URL.temporaryDirectory.appending(path: "LibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )

        let creation = try library.add(built, duration: 2)
        let stored = creation.livePhoto
        #expect(stored.identifier == built.identifier)
        #expect(FileManager.default.fileExists(atPath: stored.imageURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: stored.videoURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: built.videoURL.path(percentEncoded: false)))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Creation>()) == 1)
        _ = try await LivePhotoLoader.load(stored)

        try library.delete(creation)
        #expect(!FileManager.default.fileExists(atPath: CreationLibrary.directory(for: creation.id).path(percentEncoded: false)))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Creation>()) == 0)
    }
}

struct OrphanCleanupTests {
    @Test func removesOnlyFoldersWithoutALibraryEntry() throws {
        let container = try ModelContainer(for: Creation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let library = CreationLibrary(context: container.mainContext)
        let root = URL.temporaryDirectory.appending(path: "OrphanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let kept = Creation(id: UUID(), pairingIdentifier: "p", imageFileName: "a.heic", videoFileName: "a.mov", duration: 2)
        container.mainContext.insert(kept)
        for id in [kept.id, UUID()] {
            try FileManager.default.createDirectory(at: root.appending(path: id.uuidString), withIntermediateDirectories: true)
        }

        library.removeOrphanedFiles(in: root)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        #expect(remaining == [kept.id.uuidString])
    }

    @Test func leavesTheRealLibraryAloneWithAnInMemoryStore() throws {
        let container = try ModelContainer(for: Creation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = CreationLibrary.rootDirectory
        let before = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        CreationLibrary(context: container.mainContext).removeOrphanedFiles()
        let after = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        #expect(Set(before) == Set(after))
    }
}
