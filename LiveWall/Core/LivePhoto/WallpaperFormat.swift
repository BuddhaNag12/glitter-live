import CoreGraphics

nonisolated enum WallpaperFormat {
    /// The ~19.5:9 screen of every Face ID iPhone, capped at the 1920 px long side the Lock Screen accepts.
    static let outputSize = CGSize(width: 886, height: 1920)
    /// The widest iPhone screen (Pro Max); a sharper cover photo than this can't be seen.
    static let maximumStillWidth: CGFloat = 1320
    /// The Lock Screen reports "Motion not available" for a cover frame up to about 0.33 s into the
    /// movie, whatever its length; 0.5 s works (measured on an iPhone 17 Pro).
    static let minimumCoverTime = 0.5
    static var aspectRatio: CGFloat { outputSize.width / outputSize.height }
    static let frameRate: Int32 = 30
    /// Lock-screen motion is most reliable with short clips.
    static let clipDurations: [Double] = [1.5, 2, 3]
    static let defaultClipDuration = 3.0
}
