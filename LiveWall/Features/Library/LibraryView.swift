import AVFoundation
import ImageIO
import SwiftData
import SwiftUI

struct LibraryView: View {
    var onConvert: () -> Void

    @Query(sort: \Creation.createdAt, order: .reverse) private var creations: [Creation]
    @State private var selection: Creation?
    @Namespace private var zoom

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if creations.isEmpty {
                LibraryEmptyView(onConvert: onConvert)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(creations.count == 1 ? "1 live wallpaper" : "\(creations.count) live wallpapers")
                                    .typography(.headlineSmall)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Button(action: onConvert) {
                                    Label("New", systemImage: "plus")
                                }
                                .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(creations) { creation in
                                    Button { selection = creation } label: {
                                        CreationCard(creation: creation)
                                    }
                                    .buttonStyle(.plain)
                                    .zoomSource(id: creation.id, in: zoom, cornerRadius: 24)
                                    .accessibilityIdentifier("creation-card")
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
                .screenHeader("Library")
            }
        }
        .sheet(item: $selection) { creation in
            CreationDetailView(creation: creation)
                .zoomTransition(from: creation.id, in: zoom)
        }
        #if DEBUG
        .task { await seedDemoLibraryIfRequested() }
        #endif
    }

    #if DEBUG
    @Environment(\.modelContext) private var modelContext

    private func seedDemoLibraryIfRequested() async {
        guard DemoLaunch.seedsLibrary, creations.isEmpty else { return }
        let library = CreationLibrary(context: modelContext)
        for index in 0..<3 {
            guard let video = try? await DemoVideo.make() else { return }
            let request = LivePhotoRequest(
                sourceURL: video,
                timeRange: CMTimeRange(start: CMTime(seconds: Double(index) * 0.8, preferredTimescale: 600), duration: CMTime(seconds: 2.5, preferredTimescale: 600)),
                cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                keyFrameOffset: CMTime(seconds: 1.2, preferredTimescale: 600)
            )
            guard let result = try? await LivePhotoBuilder.build(request, in: .livePhotosDirectory) else { return }
            let creation = try? library.add(result, duration: 2.5)
            creation?.savedToPhotos = index != 1
        }
    }
    #endif
}

private struct CreationCard: View {
    let creation: Creation
    @State private var thumbnail: UIImage?

    var body: some View {
        Color.black
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    AuroraView(isAnimated: false).opacity(0.35)
                }
            }
            .overlay(alignment: .topLeading) {
                StatusPill(text: "\(creation.duration.formatted(.number.precision(.fractionLength(1))))s", dot: Theme.signalYellow)
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if creation.savedToPhotos {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle())
                        .padding(10)
                        .accessibilityLabel("Saved to Photos")
                }
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(creation.createdAt, format: .dateTime.month(.abbreviated).day())
                        .typography(.titleMedium)
                        .foregroundStyle(.white)
                    Text(creation.createdAt, format: .dateTime.hour().minute())
                        .font(.labelMedium.weight(.semibold))
                        .foregroundStyle(Theme.onMediaSecondary)
                }
                .mediaCaption()
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Wallpaper tiles are always dark media, so their glass badges stay dark too.
            .environment(\.colorScheme, .dark)
            .task(id: creation.id) {
                thumbnail = await Thumbnail.load(creation.livePhoto.imageURL, maxPixelSize: 600)
            }
    }
}

nonisolated enum Thumbnail {
    @concurrent
    static func load(_ url: URL, maxPixelSize: Int) async -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
