import SwiftUI

/// What the notch is drawn as right now. Follows `NotchMode`, plus a "drop" step
/// so opening and closing play in two beats, like Jarvis Private.
enum NotchStage: Equatable {
    case idle, peek, drop, open
}

/// Opening is one flowing motion: the narrow tab eases down out of the notch, and before it has landed
/// the panel is already widening (a gentle spring) while the text fades in.
/// Closing is smooth with no bounce: narrow, then retract slowly up.
enum NotchMotion {
    /// The narrow tab easing down: a smooth ease-out, no overshoot.
    static let drop = Animation.timingCurve(0.25, 0.9, 0.35, 1, duration: 0.28)
    /// Seconds into the drop when the widening starts, so the two blend instead of waiting for each other.
    static let expandDelay: Duration = .milliseconds(110)
    /// The widening: a soft spring with a light settle.
    static let expand = Animation.spring(duration: 0.55, bounce: 0.18)
    /// Narrowing on close: smooth, with no swell or bounce before it pulls in.
    static let collapse = Animation.easeInOut(duration: 0.3)
    /// The last step up into the notch: slow and smooth, no bounce.
    static let retractSeconds = 0.5
    static let retract = Animation.easeInOut(duration: retractSeconds)
    static let peek = Animation.spring(duration: 0.35, bounce: 0.2)

    /// The tab popping out beside the closed notch once it has closed: a quick spring with one small settle. It waits
    /// for the whole retract (it starts with it): out before the end, it sprang while the dropdown's bottom edge still
    /// showed below the notch, and a bouncier spring overshot and came back, so it read as two pumps. SwiftUI runs it
    /// at the display's full refresh rate (120 Hz on ProMotion).
    static let tabBounce = Animation.spring(duration: 0.4, bounce: 0.25).delay(retractSeconds + 0.05)
    /// The tab pulled back in when the notch opens.
    static let tabIn = Animation.easeIn(duration: 0.16)

    /// The panel's text appears while it widens: a soft fade with a slight settle from the top, then
    /// fades out quickly on close.
    static var content: AnyTransition { .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
            .animation(.easeOut(duration: 0.3).delay(0.17)),
        removal: .opacity.animation(.easeIn(duration: 0.08))) }
}
