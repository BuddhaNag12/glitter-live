import Foundation

/// Generates through the Supabase `generate` function, which holds the AI providers' keys
/// (`supabase/functions/generate`).
nonisolated struct RemoteGenerationService: GenerationService {
    private static let endpoint = CatalogConfig.projectURL.appending(path: "functions/v1/generate")

    @concurrent
    func makeImage(for request: GenerationRequest) async throws -> URL {
        let body = ["action": "image", "prompt": request.fullPrompt, "install": InstallID.value, "reward": request.reward ?? ""]
        // Long enough for the server to wait for AdMob's confirmation of the ad, then make and check the image.
        let response: ImageResponse = try await Self.call(body, timeout: 90)
        guard let data = Data(base64Encoded: response.image) else { throw GenerationError.imageFailed }
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    @concurrent
    func animate(imageAt imageURL: URL, for request: GenerationRequest) async throws -> URL {
        let image = try Data(contentsOf: imageURL).base64EncodedString()
        // Video models take the longest, often well over half a minute.
        let response: VideoResponse = try await Self.call(["action": "video", "prompt": request.fullPrompt, "image": image], timeout: 240)
        guard let videoURL = URL(string: response.videoUrl) else { throw GenerationError.videoFailed }
        let (download, _) = try await URLSession.shared.download(from: videoURL)
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: download, to: url)
        return url
    }

    static func call<Response: Decodable>(_ body: [String: String], timeout: TimeInterval) async throws -> Response {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(CatalogConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GenerationError.server((try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    struct ReportResponse: Decodable { let reported: Bool }
    private struct ImageResponse: Decodable { let image: String }
    private struct VideoResponse: Decodable { let videoUrl: String }
    private struct ErrorResponse: Decodable { let error: String }
}

/// A random ID for this install, sent to AdMob with each rewarded ad and with each generation, so the server can
/// match the two and count the daily limit. It isn't tied to the person or the device, and resets on reinstall.
nonisolated enum InstallID {
    static var value: String {
        if let id = UserDefaults.standard.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "installID")
        return id
    }
}

/// Someone flagging a generated image from the app.
nonisolated enum GenerationReport {
    enum Reason: String, CaseIterable, Identifiable {
        case sexual, violent, hateful, other

        var id: Self { self }

        var title: String {
            switch self {
            case .sexual: "Sexual content"
            case .violent: "Violence or gore"
            case .hateful: "Hateful content"
            case .other: "Something else"
            }
        }
    }

    static func send(prompt: String, reason: Reason) async throws {
        let body = ["action": "report", "prompt": prompt, "install": InstallID.value, "reason": reason.rawValue]
        let _: RemoteGenerationService.ReportResponse = try await RemoteGenerationService.call(body, timeout: 20)
    }
}

/// An AI image from the server, with motion from whichever animator fits: AI video, or the phone's own.
nonisolated struct GenerationPipeline: GenerationService {
    var images: any GenerationService
    var motion: any WallpaperAnimator

    func makeImage(for request: GenerationRequest) async throws -> URL {
        try await images.makeImage(for: request)
    }

    func animate(imageAt url: URL, for request: GenerationRequest) async throws -> URL {
        try await motion.animate(imageAt: url, for: request)
    }
}
