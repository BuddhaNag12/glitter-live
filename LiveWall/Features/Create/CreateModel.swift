import Foundation
import Observation

@Observable
final class CreateModel {
    enum Phase: Equatable {
        case composing
        case makingImage
        case animating(image: URL)
        case converting(image: URL)
        /// Trim Studio or the result, shown by `ConvertFlowView`.
        case editing
    }

    var prompt = "" {
        didSet {
            if prompt.count > GenerationRequest.maximumPromptLength {
                prompt = String(prompt.prefix(GenerationRequest.maximumPromptLength))
            }
        }
    }
    var style: WallpaperStyle = .cinematic
    private(set) var phase: Phase = .composing
    private(set) var editor: ConvertEditor?
    var errorMessage: String?
    let allowance = GenerationAllowance()

    @ObservationIgnored private let service: any GenerationService
    @ObservationIgnored private let ads: any RewardedAdPresenter
    @ObservationIgnored private var imageURL: URL?

    init(service: any GenerationService = PreviewGenerationService(), ads: any RewardedAdPresenter = PendingRewardedAds()) {
        self.service = service
        self.ads = ads
    }

    var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var canGenerate: Bool {
        switch allowance.access {
        case .dailyLimitReached, .monthlyLimitReached: false
        default: hasPrompt && phase == .composing
        }
    }

    func surprise() {
        prompt = SurprisePrompts.all.filter { $0 != prompt }.randomElement() ?? prompt
    }

    /// Image, then motion, then either straight to a saved Live Photo or into Trim Studio.
    func generate(convertsOnTheGo: Bool, library: CreationLibrary) async {
        guard canGenerate else { return }
        if case .ad = allowance.access, await !ads.present() { return }
        let request = GenerationRequest(prompt: prompt, style: style)
        do {
            phase = .makingImage
            let image = try await service.makeImage(for: request)
            imageURL = image
            phase = .animating(image: image)
            let video = try await service.animate(imageAt: image, for: request)
            allowance.recordGeneration()

            let editor = ConvertEditor(sourceURL: video, library: library)
            await editor.load()
            self.editor = editor
            if convertsOnTheGo, editor.phase == .editing {
                phase = .converting(image: image)
                await editor.export()
            }
            phase = .editing
        } catch {
            errorMessage = error.localizedDescription
            phase = .composing
        }
    }

    /// Keeps the prompt, so it can be tweaked and tried again.
    func startOver() {
        editor?.stop()
        if let url = editor?.sourceURL { try? FileManager.default.removeItem(at: url) }
        if let imageURL { try? FileManager.default.removeItem(at: imageURL) }
        editor = nil
        imageURL = nil
        phase = .composing
    }
}
