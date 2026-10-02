import Foundation

/// Where picked, downloaded and shared videos are copied, so Trim Studio always works on a file the app owns.
nonisolated enum ImportedVideos {
    static func destination(pathExtension: String) throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString).\(pathExtension.isEmpty ? "mov" : pathExtension)")
    }

    /// Copies a file the app may only borrow, such as one from Files, off the main thread since videos can be large.
    @concurrent
    static func copy(_ url: URL) async throws -> URL {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let destination = try destination(pathExtension: url.pathExtension)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

/// Videos handed over by the Share extension. They wait in the App Group container until the app next opens.
/// Compiled into both the app and the extension.
nonisolated enum SharedInbox {
    static let appGroup = "group.com.buddhanag.glitterlive"

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Keeps only the newest video, since the app opens one at a time.
    static func add(videoAt url: URL) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pathExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        try FileManager.default.copyItem(at: url, to: directory.appending(path: "\(UUID().uuidString).\(pathExtension)"))
    }

    /// Moves the waiting video, if there is one, out of the shared container.
    static func takeVideo() -> URL? {
        guard let directory,
              let file = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        else { return nil }
        do {
            let destination = try ImportedVideos.destination(pathExtension: file.pathExtension)
            try FileManager.default.moveItem(at: file, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}
