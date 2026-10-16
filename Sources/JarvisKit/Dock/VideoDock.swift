import CoreGraphics

/// A browser's Picture in Picture video held by the notch. The video window floats on every desktop below
/// Jarvis's panel, so the notch can frame it: in the dropdown it takes the music row's place, and while the
/// notch is closed it hangs under it as a mini player. The notch is drawn solid over it while it moves
/// (`covered`) and the hole fades open once it's in place, so nothing see-through ever shows.
public struct VideoDock: Sendable, Equatable {
    /// A Picture in Picture window is open, so the dropdown offers to hold it.
    public var available = false
    public var held = false
    /// Keep Large and the pointer away: the open notch is just the video, bigger. Set by the video controller
    /// once the clamshell is shut, so the notch only changes shape behind it.
    public var theater = false
    /// Mid-switch between the full dropdown and Large (see `NotchLayout.tallForTheater`).
    public var tallForTheater = false
    /// Tucked away (↑ on the mini player): the video shrinks as small as the browser allows, right under the
    /// hardware notch, and the notch deepens just enough to cover it (macOS won't let a window go off-screen).
    /// Hovering the notch, or the video icon in the side tab, brings the mini player back.
    public var tucked = false
    /// The size it got when tucked.
    public var tuckedSize: CGSize?
    /// A loose video is being dragged onto the notch: the dropdown shows an outline where it'll go.
    public var catching = false
    /// Width over height of the held video.
    public var aspect: CGFloat = 16 / 9
    /// The notch covers the video's spot (while the video moves there).
    public var covered = true
    /// The smallest the browser lets its video window be, learned when it refuses to shrink further.
    public var minimum: CGSize?

    public init() {}
}
