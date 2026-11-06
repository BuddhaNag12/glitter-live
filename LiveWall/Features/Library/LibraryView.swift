import AVFoundation
import ImageIO
import SwiftData
import SwiftUI

struct LibraryView: View {
    var onConvert: () -> Void

    @Query(sort: \Creation.createdAt, order: .reverse) private var creations: [Creation]
    @State private var selection: Creation?
    @State private var category = Category.all
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    /// Waiting for the delete confirmation: from the Delete bar or a card's long-press menu.
    @State private var pendingDeletion: [Creation] = []
    @Namespace private var zoom
    @Environment(\.modelContext) private var modelContext

    enum Category: String, CaseIterable, Identifiable {
        case all = "All", live = "Live", stills = "Stills"
        var id: Self { self }
    }

    private var visibleCreations: [Creation] {
        switch category {
        case .all: creations
        case .live: creations.filter(\.isLive)
        case .stills: creations.filter { !$0.isLive }
        }
    }

    private var countTitle: String {
        let count = visibleCreations.count
        switch category {
        case .all: return count == 1 ? "1 wallpaper" : "\(count) wallpapers"
        case .live: return count == 1 ? "1 live wallpaper" : "\(count) live wallpapers"
        case .stills: return count == 1 ? "1 still" : "\(count) stills"
        }
    }

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
                                Text(countTitle)
                                    .typography(.headlineSmall)
                                    .foregroundStyle(Theme.textPrimary)
                                    .contentTransition(.numericText())
                                Spacer()
                                headerButtons
                            }
                            categoryChips
                            if visibleCreations.isEmpty {
                                Text(category == .stills
                                     ? "Wallpapers you save from Create without motion appear here."
                                     : "Live wallpapers you make appear here.")
                                    .typography(.bodyMedium)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(visibleCreations) { creation in
                                    let isSelected = selectedIDs.contains(creation.id)
                                    Button { tap(creation) } label: {
                                        CreationCard(creation: creation, selection: isSelecting ? isSelected : nil)
                                    }
                                    .buttonStyle(.plain)
                                    .zoomSource(id: creation.id, in: zoom, cornerRadius: 24)
                                    .accessibilityIdentifier("creation-card")
                                    .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
                                    .contextMenu {
                                        if !isSelecting {
                                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = [creation] }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
                .safeAreaInset(edge: .bottom) {
                    if isSelecting { deleteBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .screenHeader("Library")
            }
        }
        .animation(.spring(duration: 0.3), value: isSelecting)
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete this wallpaper from Glitter Live?" : "Delete \(pendingDeletion.count) wallpapers from Glitter Live?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button(pendingDeletion.count == 1 ? "Delete" : "Delete \(pendingDeletion.count)", role: .destructive, action: deletePending)
        } message: {
            Text("Any copy you saved to Photos stays there.")
        }
        .sensoryFeedback(.success, trigger: creations.count) { old, new in new < old }
        .onChange(of: creations.isEmpty) { _, isEmpty in if isEmpty { endSelecting() } }
        .sheet(item: $selection) { creation in
            CreationDetailView(creation: creation)
                .zoomTransition(from: creation.id, in: zoom)
        }
        #if DEBUG
        .task { await seedDemoLibraryIfRequested() }
        #endif
    }

    @ViewBuilder
    private var headerButtons: some View {
        if isSelecting {
            let visibleIDs = Set(visibleCreations.map(\.id))
            let allSelected = !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedIDs)
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected { selectedIDs.subtract(visibleIDs) } else { selectedIDs.formUnion(visibleIDs) }
            }
            .buttonStyle(GlassPillButtonStyle())
            Button("Done", action: endSelecting)
                .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
        } else {
            Button("Select") { isSelecting = true }
                .buttonStyle(GlassPillButtonStyle())
            Button(action: onConvert) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
        }
    }

    private var deleteBar: some View {
        Button {
            pendingDeletion = creations.filter { selectedIDs.contains($0.id) }
        } label: {
            Label(selectedIDs.isEmpty ? "Select wallpapers to delete" : "Delete \(selectedIDs.count)", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPillButtonStyle(tint: Theme.danger))
        .disabled(selectedIDs.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tap(_ creation: Creation) {
        guard isSelecting else { return selection = creation }
        if selectedIDs.contains(creation.id) { selectedIDs.remove(creation.id) } else { selectedIDs.insert(creation.id) }
    }

    private func endSelecting() {
        isSelecting = false
        selectedIDs = []
    }

    private func deletePending() {
        let doomed = pendingDeletion
        pendingDeletion = []
        try? CreationLibrary(context: modelContext).delete(doomed)
        endSelecting()
    }

    private var categoryChips: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Category.allCases) { option in
                    Button(option.rawValue) {
                        withAnimation(.spring(duration: 0.3)) { category = option }
                    }
                    .buttonStyle(GlassPillButtonStyle(tint: category == option ? Theme.accent : nil))
                    .accessibilityAddTraits(category == option ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: category)
    }

    #if DEBUG
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
    /// nil outside selection mode; otherwise whether this card is selected.
    var selection: Bool? = nil
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
                Group {
                    if creation.isLive {
                        StatusPill(text: "\(creation.duration.formatted(.number.precision(.fractionLength(1))))s", dot: Theme.signalYellow)
                    } else {
                        StatusPill(text: "STILL", dot: Theme.slate, symbol: "photo")
                    }
                }
                .padding(10)
            }
            .overlay {
                if selection == true {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.accentFill, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selection {
                    Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selection ? Theme.accentFill : .black.opacity(0.25))
                        .padding(10)
                        .accessibilityHidden(true)
                } else if creation.savedToPhotos {
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
                thumbnail = await Thumbnail.load(creation.imageURL, maxPixelSize: 600)
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
