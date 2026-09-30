import SwiftUI

/// Filmstrip with a draggable trim window and cover marker. Long videos scroll so short clips stay easy to grab.
struct TimelineStrip: View {
    @Bindable var editor: ConvertEditor

    @State private var dragOrigin: (start: Double, length: Double)?
    @State private var coverDragOrigin: Double?
    /// True while a drag pushes past the shortest or longest clip, or an end of the video.
    @State private var isAtLimit = false

    private let height: CGFloat = 64
    private let handleWidth: CGFloat = 16
    private let minimumPointsPerSecond: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            let pointsPerSecond = editor.duration > 0 ? max(geometry.size.width / editor.duration, minimumPointsPerSecond) : 0
            let contentWidth = editor.duration * pointsPerSecond
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    filmstrip(width: contentWidth)
                    dimming(pointsPerSecond: pointsPerSecond, contentWidth: contentWidth)
                    trimWindow(pointsPerSecond: pointsPerSecond)
                    coverMarker(pointsPerSecond: pointsPerSecond)
                }
                .frame(width: contentWidth, height: height)
                .coordinateSpace(.named("timeline"))
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(contentWidth <= geometry.size.width)
        }
        .frame(height: height)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: isAtLimit) { _, atLimit in atLimit }
    }

    private func filmstrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(editor.thumbnails.indices, id: \.self) { index in
                Image(decorative: editor.thumbnails[index], scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width / CGFloat(max(editor.thumbnails.count, 1)), height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private func dimming(pointsPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let windowStart = editor.clipStart * pointsPerSecond
        let windowEnd = (editor.clipStart + editor.clipLength) * pointsPerSecond
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6).frame(width: max(windowStart, 0), height: height)
            Color.black.opacity(0.6)
                .frame(width: max(contentWidth - windowEnd, 0), height: height)
                .offset(x: windowEnd)
        }
        .allowsHitTesting(false)
    }

    private func trimWindow(pointsPerSecond: CGFloat) -> some View {
        let width = max(editor.clipLength * pointsPerSecond, handleWidth * 2 + 8)
        return HStack(spacing: 0) {
            // Handles sit above the middle so their enlarged hit areas win where they overlap it.
            handle(leading: true).highPriorityGesture(resizeGesture(pointsPerSecond: pointsPerSecond, leading: true)).zIndex(1)
            Color.clear
                .contentShape(Rectangle())
                .highPriorityGesture(moveGesture(pointsPerSecond: pointsPerSecond))
            handle(leading: false).highPriorityGesture(resizeGesture(pointsPerSecond: pointsPerSecond, leading: false)).zIndex(1)
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.trimHandle, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .offset(x: editor.clipStart * pointsPerSecond)
        .accessibilityElement()
        .accessibilityLabel("Clip")
        .accessibilityValue("Starts at \(editor.clipStart.formatted(.number.precision(.fractionLength(1)))) seconds")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            editor.moveClip(to: editor.clipStart + step)
            editor.restartLoop()
        }
    }

    /// The hit area grows mostly outwards, leaving the inside of the window for moving it and the cover marker.
    private func handle(leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.trimHandle)
            .frame(width: handleWidth, height: height)
            .overlay(Capsule().fill(.black.opacity(0.55)).frame(width: 3, height: 18))
            .contentShape(OutsetRectangle(leading: leading ? 14 : 4, trailing: leading ? 4 : 14))
    }

    private func coverMarker(pointsPerSecond: CGFloat) -> some View {
        let x = (editor.clipStart + editor.coverOffset) * pointsPerSecond
        let hitWidth: CGFloat = 28
        return VStack(spacing: 0) {
            Circle().fill(Theme.accent).frame(width: 12, height: 12)
            Rectangle().fill(.white).frame(width: 2)
        }
        .frame(width: hitWidth, height: height)
        .contentShape(Rectangle())
        .offset(x: x - hitWidth / 2)
        .highPriorityGesture(coverGesture(pointsPerSecond: pointsPerSecond))
        .accessibilityElement()
        .accessibilityLabel("Cover photo")
        .accessibilityValue("\(editor.coverOffset.formatted(.number.precision(.fractionLength(1)))) seconds into the clip")
        .accessibilityAdjustableAction { direction in
            moveCover(to: editor.coverOffset + (direction == .increment ? 0.1 : -0.1))
            editor.resumePreview()
        }
    }

    private func coverGesture(pointsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let origin = coverDragOrigin ?? editor.coverOffset
                coverDragOrigin = origin
                moveCover(to: origin + value.translation.width / pointsPerSecond)
            }
            .onEnded { _ in
                coverDragOrigin = nil
                editor.resumePreview()
            }
    }

    private func moveCover(to offset: Double) {
        let range = editor.coverRange
        editor.coverOffset = min(max(offset, range.lowerBound), range.upperBound)
        editor.showCoverFrame()
    }

    private func moveGesture(pointsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let origin = beginDrag()
                let proposed = origin.start + value.translation.width / pointsPerSecond
                editor.moveClip(to: proposed)
                isAtLimit = abs(editor.clipStart - proposed) > 0.001
                editor.scrub(to: editor.clipStart)
            }
            .onEnded { _ in endDrag() }
    }

    /// Shows the frame under the dragged handle, so trimming shows exactly where the clip starts or ends.
    private func resizeGesture(pointsPerSecond: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let origin = beginDrag()
                let delta = value.translation.width / pointsPerSecond
                if leading {
                    let proposed = origin.start + delta
                    editor.setClipStart(proposed)
                    isAtLimit = abs(editor.clipStart - proposed) > 0.001
                    editor.scrub(to: editor.clipStart)
                } else {
                    let proposed = origin.start + origin.length + delta
                    editor.setClipEnd(proposed)
                    let end = editor.clipStart + editor.clipLength
                    isAtLimit = abs(end - proposed) > 0.001
                    editor.scrub(to: end)
                }
            }
            .onEnded { _ in endDrag() }
    }

    private func beginDrag() -> (start: Double, length: Double) {
        if let dragOrigin { return dragOrigin }
        let origin = (editor.clipStart, editor.clipLength)
        dragOrigin = origin
        return origin
    }

    private func endDrag() {
        dragOrigin = nil
        isAtLimit = false
        editor.restartLoop()
    }
}

nonisolated private struct OutsetRectangle: Shape {
    var leading: CGFloat
    var trailing: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - leading, y: rect.minY, width: rect.width + leading + trailing, height: rect.height))
    }
}
