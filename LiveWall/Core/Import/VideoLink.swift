import Foundation
import os
import UniformTypeIdentifiers

/// Downloads a video from a direct link to the file. Pages on video sites aren't files, and saving their videos breaks
/// those sites' terms and App Review guideline 5.2.3, so they're turned away with a way forward instead.
nonisolated enum VideoLink {
    static let maximumBytes: Int64 = 1_000_000_000

    /// Sites whose videos have to be saved from their own app first, with how to do that.
    enum Site: Equatable {
        case instagram, tiktok, youtube, facebook, other(String)

        private static let hosts: [(String, Site)] = [
            ("instagram.com", .instagram), ("tiktok.com", .tiktok), ("youtube.com", .youtube), ("youtu.be", .youtube),
            ("facebook.com", .facebook), ("fb.watch", .facebook), ("x.com", .other("X")), ("twitter.com", .other("X")),
            ("vimeo.com", .other("Vimeo")), ("snapchat.com", .other("Snapchat")), ("pinterest.com", .other("Pinterest")),
            ("reddit.com", .other("Reddit")),
        ]

        init?(host: String) {
            guard let match = Self.hosts.first(where: { host == $0.0 || host.hasSuffix(".\($0.0)") }) else { return nil }
            self = match.1
        }

        var name: String {
            switch self {
            case .instagram: "Instagram"
            case .tiktok: "TikTok"
            case .youtube: "YouTube"
            case .facebook: "Facebook"
            case .other(let name): name
            }
        }

        var steps: [String] {
            switch self {
            case .instagram:
                ["Open the Reel in Instagram.", "Tap the share button (the paper plane), then Download.", "Come back and choose it from Photos."]
            case .tiktok:
                ["Open the video in TikTok.", "Tap Share, then Save video.", "Come back and choose it from Photos."]
            case .youtube:
                ["YouTube doesn't save videos to Photos.", "For your own videos, download them from YouTube Studio, or use the original from your camera roll."]
            case .facebook:
                ["For your own videos, tap ⋯ on the video, then Download.", "Come back and choose it from Photos."]
            case .other(let name):
                ["If \(name) offers Save or Download on the video, use it to save it to Photos.", "Come back and choose it from Photos."]
            }
        }

        /// The download option only appears where the creator allows it.
        var note: String? {
            switch self {
            case .instagram, .tiktok: "Download is there for your own videos, and for others' when the creator allows it."
            default: nil
            }
        }
    }

    enum Problem: LocalizedError, Equatable {
        case notALink, insecure, videoSite(Site), notAVideo, tooLarge, unreachable

        var errorDescription: String? {
            switch self {
            case .notALink: "That doesn't look like a link. Paste one that starts with https://."
            case .insecure: "That link isn't secure. Use one that starts with https://."
            case .videoSite(let site): "Videos on \(site.name) can't be downloaded from a link. Save it to Photos from the \(site.name) app instead."
            case .notAVideo: "That link opens a web page, not a video file. Use a direct link to an .mp4 or .mov file."
            case .tooLarge: "That video is over 1 GB. Trim it shorter first, or use a smaller copy."
            case .unreachable: "That link couldn't be opened. Check it and your connection, then try again."
            }
        }
    }

    /// Checks the text and rewrites Dropbox and Google Drive share links into their direct-download form.
    static func url(from text: String) throws(Problem) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), host.contains(".") else { throw .notALink }
        guard scheme == "https" else { throw scheme == "http" ? .insecure : .notALink }
        if let site = Site(host: host) { throw .videoSite(site) }

        if host.hasSuffix("dropbox.com") {
            var items = (components.queryItems ?? []).filter { $0.name != "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            components.queryItems = items
        } else if host == "drive.google.com", let id = driveFileID(in: components) {
            components = URLComponents(string: "https://drive.google.com/uc?export=download&id=\(id)")!
        }
        guard let url = components.url else { throw .notALink }
        return url
    }

    /// Reports progress from 0 to 1 while it can tell, and returns the video copied into the app's imports.
    @concurrent
    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let watcher = DownloadWatcher()
        let poller = Task {
            while !Task.isCancelled {
                if let task = watcher.task {
                    if task.countOfBytesExpectedToReceive > maximumBytes || task.countOfBytesReceived > maximumBytes {
                        watcher.isTooLarge = true
                        task.cancel()
                    }
                    progress(task.progress.fractionCompleted)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { poller.cancel() }

        let file: URL, response: URLResponse
        do {
            (file, response) = try await URLSession.shared.download(from: url, delegate: watcher)
        } catch {
            if watcher.isTooLarge { throw Problem.tooLarge }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw Problem.unreachable
        }
        defer { try? FileManager.default.removeItem(at: file) }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Problem.unreachable }
        let type = response.mimeType.flatMap { UTType(mimeType: $0) }
        let linkType = UTType(filenameExtension: url.pathExtension)
        let pathExtension: String
        if let type, type.conforms(to: .movie) {
            pathExtension = type.preferredFilenameExtension ?? "mp4"
        } else if let linkType, linkType.conforms(to: .movie), type == nil || type == .data {
            // Some hosts send video as plain bytes, so the link's own extension decides.
            pathExtension = url.pathExtension
        } else {
            throw Problem.notAVideo
        }
        let destination = try ImportedVideos.destination(pathExtension: pathExtension)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    private static func driveFileID(in components: URLComponents) -> String? {
        if let id = components.queryItems?.first(where: { $0.name == "id" })?.value { return id }
        let parts = components.path.split(separator: "/")
        guard let index = parts.firstIndex(of: "d"), parts.indices.contains(index + 1) else { return nil }
        return String(parts[index + 1])
    }
}

/// Catches the download task as URLSession creates it, so its progress can be read.
nonisolated private final class DownloadWatcher: NSObject, URLSessionTaskDelegate, Sendable {
    private let state = OSAllocatedUnfairLock<(task: URLSessionTask?, isTooLarge: Bool)>(initialState: (nil, false))

    var task: URLSessionTask? { state.withLock { $0.task } }

    var isTooLarge: Bool {
        get { state.withLock { $0.isTooLarge } }
        set { state.withLock { $0.isTooLarge = newValue } }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        state.withLock { $0.task = task }
    }
}
