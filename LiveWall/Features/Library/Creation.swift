import Foundation
import SwiftData

/// A live wallpaper the user made. The still and movie live in the app's own storage, so the
/// wallpaper can be saved again even if the user deletes it from Photos.
@Model
final class Creation {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// The UUID pairing the still and movie; also their file names.
    var pairingIdentifier: String
    var imageFileName: String
    var videoFileName: String
    var duration: Double
    var savedToPhotos: Bool
    /// False for generated wallpapers saved without motion, which have no movie. Defaults to true, so
    /// wallpapers saved before stills existed migrate as live ones.
    var isLive: Bool = true

    init(id: UUID, pairingIdentifier: String, imageFileName: String, videoFileName: String, duration: Double, savedToPhotos: Bool = false, isLive: Bool = true) {
        self.id = id
        self.createdAt = .now
        self.pairingIdentifier = pairingIdentifier
        self.imageFileName = imageFileName
        self.videoFileName = videoFileName
        self.duration = duration
        self.savedToPhotos = savedToPhotos
        self.isLive = isLive
    }

    var imageURL: URL {
        CreationLibrary.directory(for: id).appending(path: imageFileName)
    }

    var livePhoto: LivePhotoResult {
        let directory = CreationLibrary.directory(for: id)
        return LivePhotoResult(
            identifier: pairingIdentifier,
            imageURL: directory.appending(path: imageFileName),
            videoURL: directory.appending(path: videoFileName)
        )
    }
}

struct CreationLibrary {
    let context: ModelContext

    nonisolated static var rootDirectory: URL {
        #if DEBUG
        // Demo runs use an in-memory store, so their files go somewhere temporary too.
        if DemoLaunch.isDemo { return URL.temporaryDirectory.appending(path: "DemoCreations", directoryHint: .isDirectory) }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Creations", directoryHint: .isDirectory)
    }

    nonisolated static func directory(for id: UUID) -> URL {
        rootDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// Moves a freshly built Live Photo into the library.
    @discardableResult
    func add(_ result: LivePhotoResult, duration: Double) throws -> Creation {
        let id = UUID()
        let directory = Self.directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageName = result.imageURL.lastPathComponent
        let videoName = result.videoURL.lastPathComponent
        try FileManager.default.moveItem(at: result.imageURL, to: directory.appending(path: imageName))
        try FileManager.default.moveItem(at: result.videoURL, to: directory.appending(path: videoName))

        let creation = Creation(id: id, pairingIdentifier: result.identifier, imageFileName: imageName, videoFileName: videoName, duration: duration)
        context.insert(creation)
        try context.save()
        return creation
    }

    /// Deletes folders that no Library entry points to, such as leftovers from an interrupted save.
    /// Skips entirely if the Library can't be read or isn't the persistent one, so a failed fetch or an
    /// in-memory fallback store never looks like an empty Library.
    func removeOrphanedFiles(in root: URL = Self.rootDirectory) {
        guard context.container.configurations.allSatisfy({ !$0.isStoredInMemoryOnly }) || root != Self.rootDirectory,
              let creations = try? context.fetch(FetchDescriptor<Creation>()) else { return }
        let known = Set(creations.map(\.id.uuidString))
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !known.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Copies a still into the library. It's only added once it's in Photos, so it's marked saved.
    @discardableResult
    func addStill(_ imageURL: URL) throws -> Creation {
        let id = UUID()
        let directory = Self.directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = imageURL.lastPathComponent
        try FileManager.default.copyItem(at: imageURL, to: directory.appending(path: name))

        let creation = Creation(id: id, pairingIdentifier: "", imageFileName: name, videoFileName: "", duration: 0, savedToPhotos: true, isLive: false)
        context.insert(creation)
        try context.save()
        return creation
    }

    /// Removes the app's copy only; anything already saved to Photos stays there.
    func delete(_ creation: Creation) throws {
        try? FileManager.default.removeItem(at: Self.directory(for: creation.id))
        context.delete(creation)
        try context.save()
    }
}
