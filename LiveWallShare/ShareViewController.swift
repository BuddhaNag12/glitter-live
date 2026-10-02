import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → Glitter Live": copies the video into the App Group, where the app picks it up the next time it opens.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(context: extensionContext))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareView: View {
    let context: NSExtensionContext?

    private enum Step: Equatable { case copying, ready, failed(String) }
    @State private var step = Step.copying

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Spacer()
                switch step {
                case .copying:
                    ProgressView().controlSize(.large)
                    Text("Adding video…").font(.headline)
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .symbolEffect(.bounce, value: step)
                    Text("Ready in Glitter Live").font(.title2.bold())
                    Text("Open Glitter Live and the video will be waiting in Convert, ready to trim.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Couldn't add this video").font(.title3.bold())
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
                if step != .copying {
                    Button {
                        context?.completeRequest(returningItems: nil)
                    } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(24)
            .navigationTitle("Glitter Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { context?.cancelRequest(withError: CocoaError(.userCancelled)) }
                }
            }
        }
        .tint(Color(red: 0.15, green: 0.39, blue: 0.92))
        .task { await importVideo() }
    }

    private func importVideo() async {
        let provider = context?.inputItems
            .compactMap { ($0 as? NSExtensionItem)?.attachments }
            .joined()
            .first { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
        guard let provider else {
            step = .failed("Only videos can be shared to Glitter Live.")
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // The file is only valid inside this callback, which runs off the main thread.
                _ = provider.loadFileRepresentation(for: .movie, openInPlace: false) { @Sendable url, _, error in
                    do {
                        guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                        try SharedInbox.add(videoAt: url)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            step = .ready
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
