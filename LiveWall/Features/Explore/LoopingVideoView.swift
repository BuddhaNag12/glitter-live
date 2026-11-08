import AVFoundation
import SwiftUI

/// Muted, looping video that only holds a player while it's playing, so a grid of them stays cheap.
/// Until the first frame arrives it's transparent, so whatever sits underneath (a thumbnail) shows through.
/// It plays the cached download, never the remote URL: streaming refetched the file on every play and loop,
/// which used up the Supabase egress quota.
struct LoopingVideoView: View {
    let wallpaper: Wallpaper
    var isPlaying: Bool

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            }
        }
        .task(id: isPlaying) {
            if isPlaying { await start() } else { stop() }
        }
        .onDisappear(perform: stop)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func start() async {
        guard player == nil, let file = try? await CatalogService.downloadMedia(wallpaper), !Task.isCancelled else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: file))
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
