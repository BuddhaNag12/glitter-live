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

    /// List or grid; the choice is remembered.
    @AppStorage("library.layout") private var layout = Layout.list

    enum Layout: String {
        case list, grid
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        Group {
            if creations.isEmpty {
                LibraryEmptyView(onConvert: onConvert)
            } else {
                Group {
                    switch layout {
                    case .list: listLayout
                    case .grid: gridLayout
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // Only once something is picked, so the bar never sits there doing nothing.
                    if isSelecting && !selectedIDs.isEmpty { deleteBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .screenHeader("Library")
            }
        }
        .animation(.spring(duration: 0.3), value: isSelecting)
        .animation(.spring(duration: 0.3), value: selectedIDs.isEmpty)
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

    /// A List rather than a scroll view, for the system's swipe-to-delete.
    private var listLayout: some View {
        List {
            header
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(Array(visibleCreations.enumerated()), id: \.element.id) { index, creation in
                item(creation, index: index)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelecting {
                            // Not role .destructive: that removes the row before the confirmation is answered.
                            Button { pendingDeletion = [creation] } label: { Label("Delete", systemImage: "trash") }
                                .tint(Theme.danger)
                        }
                    }
            }
            countFooter
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .transition(.opacity)
    }

    private var gridLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(Array(visibleCreations.enumerated()), id: \.element.id) { index, creation in
                        item(creation, index: index)
                    }
                }
                countFooter.padding(.top, 6)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                headerButtons
            }
            HStack(spacing: 8) {
                categoryChips
                Spacer(minLength: 0)
                if !isSelecting {
                    // Selecting one wallpaper is just a swipe or a long-press, so Select needs two or more.
                    if visibleCreations.count > 1 {
                        Button("Select") { isSelecting = true }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                    Button {
                        withAnimation(.spring(duration: 0.4)) { layout = layout == .list ? .grid : .list }
                    } label: {
                        Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(CircleIconButtonStyle(size: 40))
                    .accessibilityLabel(layout == .list ? "Show as Grid" : "Show as List")
                    .sensoryFeedback(.selection, trigger: layout)
                }
            }
            if visibleCreations.isEmpty {
                Text(category == .stills
                     ? "Wallpapers you save from Create without motion appear here."
                     : "Live wallpapers you make appear here.")
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
    }

    /// How many wallpapers are shown, quietly at the end, like Photos' item count.
    @ViewBuilder
    private var countFooter: some View {
        if !visibleCreations.isEmpty {
            Text(countTitle)
                .font(.labelMedium.weight(.regular))
                .foregroundStyle(Theme.textTertiary)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
        }
    }

    private func item(_ creation: Creation, index: Int) -> some View {
        let isSelected = selectedIDs.contains(creation.id)
        return Button { tap(creation) } label: {
            switch layout {
            case .list: CreationRow(creation: creation, selection: isSelecting ? isSelected : nil, zoom: zoom)
            case .grid: CreationTile(creation: creation, selection: isSelecting ? isSelected : nil, zoom: zoom)
            }
        }
        .buttonStyle(.plain)
        .appearsIn(index)
        .accessibilityIdentifier("creation-card")
        .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
        .contextMenu {
            if !isSelecting {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = [creation] }
            }
        }
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
            Label("Delete \(selectedIDs.count)", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPillButtonStyle(tint: Theme.danger))
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

/// One wallpaper in the Library list: its thumbnail, kind and length, when it was made, and whether it's in Photos.
private struct CreationRow: View {
    let creation: Creation
    /// nil outside selection mode; otherwise whether this row is selected.
    var selection: Bool? = nil
    let zoom: Namespace.ID
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Color.black
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(width: 38)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        AuroraView(isAnimated: false).opacity(0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.specularRim, lineWidth: 1))
                // The detail sheet zooms out of the thumbnail.
                .zoomSource(id: creation.id, in: zoom, cornerRadius: 8)

            // Date on top; the time below it, with the kind and length at the far end of that line.
            VStack(alignment: .leading, spacing: 10) {
                Text(creation.createdAt, format: .dateTime.month(.abbreviated).day())
                    .typography(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text(creation.createdAt, format: .dateTime.hour().minute())
                    .font(.labelMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            if let selection {
                Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selection ? Theme.accentFill : Theme.textTertiary)
                    .accessibilityHidden(true)
            } else {
                // Live badge in the corner; the Photos status as a tag below it.
                VStack(alignment: .trailing) {
                    if creation.isLive {
                        Image(systemName: "livephoto")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.signalYellow)
                            .accessibilityLabel("Live, \(creation.duration.formatted(.number.precision(.fractionLength(1)))) seconds")
                    }
                    Spacer(minLength: 0)
                    PhotosTag(isSaved: creation.savedToPhotos)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selection == true ? Theme.accentFill.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glass(.surface, cornerRadius: 18)
        .overlay {
            if selection == true {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accentFill, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: creation.id) {
            thumbnail = await Thumbnail.load(creation.imageURL, maxPixelSize: 240)
        }
    }

}

/// Whether a wallpaper is in Photos yet: a blue "In Photos" tag, or a muted "Not saved" one.
private struct PhotosTag: View {
    let isSaved: Bool

    var body: some View {
        Label(isSaved ? "In Photos" : "Not saved", systemImage: isSaved ? "checkmark" : "arrow.down")
            .labelStyle(.titleAndIcon)
            .font(.labelSmall)
            .foregroundStyle(isSaved ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSaved ? Theme.accentFill.opacity(0.18) : Theme.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(isSaved ? .clear : Theme.border, lineWidth: 1))
    }
}

/// One wallpaper in the Library grid: the thumbnail with a live badge, the Photos status and the date.
private struct CreationTile: View {
    let creation: Creation
    /// nil outside selection mode; otherwise whether this tile is selected.
    var selection: Bool? = nil
    let zoom: Namespace.ID
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
                if creation.isLive {
                    Image(systemName: "livephoto")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.signalYellow)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selection {
                    Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selection ? Theme.accentFill : .black.opacity(0.3))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                // The date and, as a bare glyph rather than a button-like circle, whether it's in Photos.
                HStack {
                    Text(creation.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.labelSmall)
                    Spacer(minLength: 4)
                    if selection == nil {
                        Image(systemName: creation.savedToPhotos ? "checkmark" : "arrow.down")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(creation.savedToPhotos ? Theme.accent : .white.opacity(0.7))
                            .accessibilityLabel(creation.savedToPhotos ? "In Photos" : "Not saved")
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selection == true ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.specularRim), lineWidth: selection == true ? 3 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .zoomSource(id: creation.id, in: zoom, cornerRadius: 14)
            .accessibilityElement(children: .combine)
            .task(id: creation.id) {
                thumbnail = await Thumbnail.load(creation.imageURL, maxPixelSize: 400)
            }
    }
}

private extension View {
    func appearsIn(_ index: Int) -> some View {
        modifier(AppearsIn(index: index))
    }
}

/// Fades and rises into place as it comes into view, the first screenful a beat apart.
/// Reduce Motion keeps just the fade.
private struct AppearsIn: ViewModifier {
    let index: Int
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isMoving = !isShown && !reduceMotion
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isMoving ? 0.94 : 1)
            .offset(y: isMoving ? 14 : 0)
            .onAppear {
                // Later items appear as they're scrolled to, without waiting behind the first screenful.
                withAnimation(.spring(duration: 0.45, bounce: 0.15).delay(index < 12 ? Double(index) * 0.035 : 0)) { isShown = true }
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
