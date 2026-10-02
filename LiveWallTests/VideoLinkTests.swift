import Foundation
import Testing
@testable import LiveWall

struct VideoLinkTests {
    @Test func acceptsDirectVideoLinks() throws {
        #expect(try VideoLink.url(from: "  https://example.com/clip.mp4 ").absoluteString == "https://example.com/clip.mp4")
    }

    @Test func turnsAwayVideoSitesAndInsecureLinks() {
        #expect(throws: VideoLink.Problem.videoSite(.youtube)) { try VideoLink.url(from: "https://www.youtube.com/watch?v=abc") }
        #expect(throws: VideoLink.Problem.videoSite(.instagram)) { try VideoLink.url(from: "https://instagram.com/reel/abc") }
        #expect(throws: VideoLink.Problem.insecure) { try VideoLink.url(from: "http://example.com/clip.mp4") }
        #expect(throws: VideoLink.Problem.notALink) { try VideoLink.url(from: "clip.mp4") }
    }

    @Test func rewritesShareLinksToDirectDownloads() throws {
        #expect(try VideoLink.url(from: "https://www.dropbox.com/s/abc/clip.mp4?dl=0").absoluteString == "https://www.dropbox.com/s/abc/clip.mp4?dl=1")
        #expect(try VideoLink.url(from: "https://drive.google.com/file/d/FILE123/view?usp=sharing").absoluteString
            == "https://drive.google.com/uc?export=download&id=FILE123")
    }
}
