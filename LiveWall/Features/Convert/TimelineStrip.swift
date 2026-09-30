import SwiftUI

/// Filmstrip with a draggable trim window. Long videos scroll so short clips stay easy to grab.
struct TimelineStrip: View {
    @Bindable var editor: ConvertEditor

    @State private var dragOrigin: (start: Double, length: Double)?

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
            handle.highPriorityGesture(resizeGesture(pointsPerSecond: pointsPerSecond, leading: true))
            Color.clear
                .contentShape(Rectangle())
                .highPriorityGesture(moveGesture(pointsPerSecond: pointsPerSecond))
            handle.highPriorityGesture(resizeGesture(pointsPerSecond: pointsPerSecond, leading: false))
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

    private var handle: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.trimHandle)
            .frame(width: handleWidth, height: height)
            .overlay(Capsule().fill(.black.opacity(0.55)).frame(width: 3, height: 18))
            .contentShape(Rectangle().inset(by: -8))
    }

    private func coverMarker(pointsPerSecond: CGFloat) -> some View {
        let x = (editor.clipStart + editor.coverOffset) * pointsPerSecond
        return VStack(spacing: 0) {
            Circle().fill(Theme.accent).frame(width: 10, height: 10)
            Rectangle().fill(.white).frame(width: 2)
        }
        .frame(width: 10, height: height)
        .offset(x: x - 5)
        .allowsHitTesting(false)
    }

    private func moveGesture(pointsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let origin = beginDrag()
                editor.moveClip(to: origin.start + value.translation.width / pointsPerSecond)
            }
            .onEnded { _ in endDrag() }
    }

    private func resizeGesture(pointsPerSecond: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let origin = beginDrag()
                let delta = value.translation.width / pointsPerSecond
                if leading {
                    editor.setClipStart(origin.start + delta)
                } else {
                    editor.setClipEnd(origin.start + origin.length + delta)
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
        editor.restartLoop()
    }
}
