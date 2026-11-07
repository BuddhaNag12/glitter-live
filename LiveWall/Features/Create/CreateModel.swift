import Foundation
import Observation

@Observable
final class CreateModel {
    enum Phase: Equatable {
        case composing
        case makingImage
        /// The finished still, ready to save or to bring to life.
        case image(URL)
        case addingMotion(image: URL)
        /// The live preview, Trim Studio, or the saved result, shown by `ConvertFlowView`.
        case live
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
    /// The still has been saved to Photos, so its button becomes "Set as Wallpaper".
    private(set) var savedStill = false
    var errorMessage: String?
    let allowance: GenerationAllowance

    @ObservationIgnored private let service: any GenerationService
    @ObservationIgnored private let ads: any RewardedAdPresenter
    @ObservationIgnored private var imageURL: URL?
    @ObservationIgnored private var surpriseQueue: [String] = []

    init(
        service: (any GenerationService)? = nil,
        ads: any RewardedAdPresenter = RewardedAds.shared,
        allowance: GenerationAllowance = GenerationAllowance()
    ) {
        self.service = service ?? Self.defaultService
        self.ads = ads
        self.allowance = allowance
    }

    private static var defaultService: any GenerationService {
        #if DEBUG
        if DemoLaunch.usesPreviewGenerator { return PreviewGenerationService() }
        #endif
        let remote = RemoteGenerationService()
        return GenerationPipeline(images: remote, motion: FeatureFlags.aiMotion ? remote : DepthMotionService())
    }

    var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var canGenerate: Bool {
        switch allowance.access {
        case .dailyLimitReached, .monthlyLimitReached: false
        default:
            switch phase {
            case .composing, .image: hasPrompt
            default: false
            }
        }
    }

    /// Goes through every prompt in a shuffled order before any repeats.
    func surprise() {
        if surpriseQueue.isEmpty { surpriseQueue = SurprisePrompts.all.shuffled().filter { $0 != prompt } }
        prompt = surpriseQueue.removeLast()
    }

    /// Makes only the still. It's the one step that counts as a generation; motion is added on the phone for free.
    func generate() async {
        guard canGenerate else { return }
        var reward: String?
        if case .ad = allowance.access {
            // The server only generates for an ad Google has confirmed, so there's no way round a missing one.
            let id = UUID().uuidString
            switch await ads.present(rewardID: id) {
            case .watched: reward = id
            case .closedEarly: return
            case .unavailable:
                errorMessage = "No ad is available right now. Try again in a minute."
                return
            }
        }
        let previous = imageURL
        let returnPhase = phase
        do {
            phase = .makingImage
            let image = try await service.makeImage(for: GenerationRequest(prompt: prompt, style: style, reward: reward))
            allowance.recordGeneration()
            if let previous { try? FileManager.default.removeItem(at: previous) }
            imageURL = image
            savedStill = false
            phase = .image(image)
        } catch {
            errorMessage = error.localizedDescription
            phase = returnPhase
        }
    }

    /// Flags the current image for review. Only the description and the reason are sent, never the image.
    func report(_ reason: GenerationReport.Reason) async -> Bool {
        do {
            try await GenerationReport.send(prompt: GenerationRequest(prompt: prompt, style: style).fullPrompt, reason: reason)
            return true
        } catch {
            errorMessage = "The report couldn't be sent. Check your connection and try again."
            return false
        }
    }

    func saveStill(library: CreationLibrary) async {
        guard let imageURL else { return }
        do {
            let still = try WallpaperStill.make(from: imageURL)
            try await LivePhotoSaver.saveStill(still)
            // A library failure shouldn't undo a save that already reached Photos.
            try? library.addStill(still)
            savedStill = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Brings the still to life and shows it as a Live Photo preview, saved only when asked.
    func addMotion(library: CreationLibrary) async {
        guard case .image(let image) = phase else { return }
        do {
            phase = .addingMotion(image: image)
            let video = try await service.animate(imageAt: image, for: GenerationRequest(prompt: prompt, style: style))
            let editor = ConvertEditor(sourceURL: video, library: library)
            await editor.load()
            self.editor = editor
            await editor.export(savesToPhotos: false)
            phase = .live
        } catch {
            errorMessage = error.localizedDescription
            phase = .image(image)
        }
    }

    /// Leaves the live version and returns to the still, which is kept.
    func backToStill() {
        discardEditor()
        if let imageURL { phase = .image(imageURL) } else { phase = .composing }
    }

    /// Keeps the prompt, so it can be tweaked and tried again.
    func editPrompt() {
        discardEditor()
        if let imageURL { try? FileManager.default.removeItem(at: imageURL) }
        imageURL = nil
        phase = .composing
    }

    private func discardEditor() {
        editor?.stop()
        if let url = editor?.sourceURL { try? FileManager.default.removeItem(at: url) }
        editor = nil
    }
}
