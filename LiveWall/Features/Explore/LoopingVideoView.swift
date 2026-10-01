import AVFoundation
import SwiftUI

/// Muted, looping video that only holds a player while it's playing, so a grid of them stays cheap.
/// Until the first frame arrives it's transparent, so whatever sits underneath (a thumbnail) shows through.
struct LoopingVideoView: View {
    let url: URL
    var isPlaying: Bool

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            }
        }
        .onChange(of: isPlaying, initial: true) { _, playing in
            playing ? start() : stop()
        }
        .onDisappear(perform: stop)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func start() {
        guard player == nil else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
    }
}
