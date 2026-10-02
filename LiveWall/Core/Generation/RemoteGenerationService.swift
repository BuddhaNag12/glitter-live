import Foundation

/// Generates through the Supabase `generate` function, which holds the AI providers' keys
/// (`supabase/functions/generate`).
nonisolated struct RemoteGenerationService: GenerationService {
    private static let endpoint = CatalogConfig.projectURL.appending(path: "functions/v1/generate")

    @concurrent
    func makeImage(for request: GenerationRequest) async throws -> URL {
        let response: ImageResponse = try await call(["action": "image", "prompt": request.fullPrompt], timeout: 60)
        guard let data = Data(base64Encoded: response.image) else { throw GenerationError.imageFailed }
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    @concurrent
    func animate(imageAt imageURL: URL, for request: GenerationRequest) async throws -> URL {
        let image = try Data(contentsOf: imageURL).base64EncodedString()
        // Video models take the longest, often well over half a minute.
        let response: VideoResponse = try await call(["action": "video", "prompt": request.fullPrompt, "image": image], timeout: 240)
        guard let videoURL = URL(string: response.videoUrl) else { throw GenerationError.videoFailed }
        let (download, _) = try await URLSession.shared.download(from: videoURL)
        let url = URL.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: download, to: url)
        return url
    }

    private func call<Response: Decodable>(_ body: [String: String], timeout: TimeInterval) async throws -> Response {
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

    private struct ImageResponse: Decodable { let image: String }
    private struct VideoResponse: Decodable { let videoUrl: String }
    private struct ErrorResponse: Decodable { let error: String }
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
