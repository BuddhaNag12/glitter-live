import Observation
import Foundation

/// A video that arrived from outside the Convert screen, such as through the Share extension, waiting to open in Trim Studio.
@Observable
final class IncomingVideo {
    var url: URL?

    /// Picks up a video the Share extension left while the app was in the background.
    func checkInbox() -> Bool {
        guard let video = SharedInbox.takeVideo() else { return false }
        if let url { try? FileManager.default.removeItem(at: url) }
        url = video
        return true
    }
}
