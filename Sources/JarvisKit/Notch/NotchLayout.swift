import CoreGraphics

/// Sizes and positions of the notch in each mode, in screen coordinates
/// (AppKit style: origin bottom-left). Everything hangs from the top edge,
/// centered on the hardware notch.
public struct NotchLayout: Sendable, Equatable {
    /// The hardware notch, or the fallback pill on Macs without one.
    public var notch: CGRect
    /// True when `notch` is the fallback pill (a display without a hardware notch), which shows the ticker.
    public var isPill = false
    public var peekGrowth = CGSize(width: 80, height: 4)
    /// How far the short tab hangs below the notch on the first beat of opening.
    public var dropDepth: CGFloat = 20
    public var openSize = CGSize(width: 560, height: 218 - 2 * NotchLayout.inputBarLift)
    /// A further lift for the search field alone, evening out the gaps above and below it.
    public static let inputBarNudge: CGFloat = 5
    /// Room under the search field, down to the panel's bottom edge (part of `openSize`'s height).
    public static let inputBarBottom: CGFloat = 10
    /// The search field is moved up this much (and the panel made twice as much shorter), trimming the gap
    /// above it without changing the one below.
    public static let inputBarLift: CGFloat = 4
    /// Extra room in the open panel for the caption (live words or the answer). It replaces the "TODAY" list.
    public var captionHeight: CGFloat = NotchLayout.defaultCaptionHeight
    public static let defaultCaptionHeight: CGFloat = 110
    /// A kept caption grows to fit its answer, up to this.
    public static let maxCaptionHeight: CGFloat = 300
    public var showsCaption = false
    /// Running timers, alarms and reminders listed above "TODAY", one row each.
    public var timerRows = 0
    public static let maxTimerRows = 4
    /// Rows in the open panel's "TODAY" list: today's events, then what's due (0 hides the list).
    public var agendaRows = 0
    public static let maxAgendaRows = 4
    public static let agendaRowHeight: CGFloat = 20
    /// The "TODAY" heading above the rows.
    public static let agendaHeaderHeight: CGFloat = 18
    /// Space between the bottom of the list and the music row.
    public static let agendaGap: CGFloat = 6
    /// Extra room around the pointer target so it is easy to hit.
    public var hoverSlop: CGFloat = 6
    /// A held video's width over height (nil when none is held). Closed, the notch grows down around it as a
    /// mini player as wide as the notch; open, it takes the music row's place.
    public var videoAspect: CGFloat?
    /// The closed notch grows this much wider on each side around the mini player.
    public static let miniGrowth: CGFloat = 17
    /// Margin between the mini player and the notch's edges (and under the hardware notch).
    public static let videoPad: CGFloat = 3
    /// The hole a video shows through: this round, inset this far inside the video.
    public static let videoHoleRadius: CGFloat = 16
    public static let videoHoleInset: CGFloat = 2
    /// The notch's bottom corners around a video (mini player and Large alike): concentric with the hole's.
    public static let videoCornerRadius: CGFloat = videoHoleRadius + videoHoleInset + videoPad
    /// Open, the video sits on the right of the time row.
    public static let openVideoHeight: CGFloat = 164
    /// Added to the open dropdown's top band (tabs, Video, Keep Info, Settings), for room above and below them.
    public static let bandPad: CGFloat = 12
    /// A tucked video's size: it waits right of the notch under the side tab.
    public var tuckedVideo: CGSize?
    /// A video can be held (the Video button shows): the dropdown is wide enough for it beside Keep.
    public var offersVideo = false
    /// The open notch is just the held video, bigger (Keep Large, pointer away).
    public var theater = false
    /// Switching between the full dropdown and Large: the dropdown is at least as deep as Large, so the video
    /// (and its clamshell) never hang out below it while they move.
    public var tallForTheater = false
    public static let theaterVideoHeight: CGFloat = 270
    /// The smallest the browser lets its video window be, if known.
    public var videoMinimum: CGSize?
    /// The tab's content is folded away (a video is held and no tab was clicked).
    public var hidesContent = false
    /// A folder held in the notch (or the outline while a Finder window is dragged over) takes the
    /// "TODAY" list's place.
    public var showsShelf = false
    public static let shelfHeight: CGFloat = 170
    /// The Web tab made large: as deep as Large's video, plus its toolbar.
    public var browserLarge = false
    public static let browserLargeHeight: CGFloat = NotchLayout.theaterVideoHeight + 40
    /// A video full screen in the Web tab, with that tab showing (not folded or switched away): closed, the notch
    /// grows down around the page as a medium player, a
    /// little bigger than a held video's mini player (unless a video is held: that one's mini player wins).
    public var browserMini = false
    public static let mediumGrowth: CGFloat = 36
    /// The medium player's size (16:9), when it shows.
    public var mediumVideoSize: CGSize? {
        guard browserMini, videoAspect == nil else { return nil }
        let width = notch.width + 2 * Self.mediumGrowth - 2 * Self.videoPad
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }
    /// Hovering the medium player drops it down a little, like the side tab, before a click opens the dropdown.
    public static let mediumPeek = CGSize(width: 12, height: 10)
    /// How deep the tab's content is (Finder, Monitor, Web, the drop box).
    public var shelfDepth: CGFloat { browserLarge ? Self.browserLargeHeight : Self.shelfHeight }
    /// A tab on the notch's right holds icons: held apps (and a held folder's, or a spot for an app being
    /// dragged). It stays out while the notch is closed; the open dropdown covers it.
    public var tabSlots = 0
    public var showsTab: Bool { tabSlots > 0 }
    public static let tabSlotWidth: CGFloat = 26

    public init(notch: CGRect) {
        self.notch = notch
    }

    public func size(for mode: NotchMode) -> CGSize {
        switch mode {
        case .idle: return closedSize
        case .peek where mediumVideoSize != nil:
            return CGSize(width: closedSize.width + Self.mediumPeek.width, height: closedSize.height + Self.mediumPeek.height)
        case .peek: return CGSize(width: closedSize.width + peekGrowth.width, height: closedSize.height + peekGrowth.height)
        case .open where theater && theaterVideoSize != nil:
            return CGSize(width: max(notch.width, theaterVideoSize!.width + 2 * Self.videoPad),
                   height: notch.height + theaterVideoSize!.height + 1.75 * Self.videoPad)
        // Wide enough with a video for Video, Keep Info and Settings right of the notch.
        case .open:
            let full = CGSize(width: max(openSize.width, notch.width, (openVideoSize?.width ?? 0) + Self.besideVideo, offersVideo ? 640 : 0),
                              height: max(openSize.height, notch.height) + Self.bandPad
                                  + (showsCaption ? captionHeight : hidesContent ? 0 : showsShelf ? shelfDepth : agendaHeight)
                                  // The video row is taller than the time row it replaces (the music moves into
                                  // it), so the search field stays inside under it.
                                  + (videoAspect == nil ? 0 : Self.openVideoHeight - 106))
            guard tallForTheater, let big = theaterVideoSize else { return full }
            return CGSize(width: full.width, height: max(full.height, notch.height + big.height + 1.75 * Self.videoPad))
        }
    }

    /// The closed notch: the hardware notch, grown down around the mini player when a video is held (or the
    /// medium player, for the Web tab's full-screen video).
    private var closedSize: CGSize {
        guard let mini = miniVideoSize ?? mediumVideoSize else { return notch.size }
        return CGSize(width: mini.width + 2 * Self.videoPad, height: notch.height + mini.height + 1.75 * Self.videoPad)
    }

    private var miniVideoSize: CGSize? {
        videoAspect.map { aspect in
            let width = notch.width + 2 * Self.miniGrowth - 2 * Self.videoPad
            return atLeastMinimum(CGSize(width: width, height: (width / aspect).rounded()), aspect: aspect)
        }
    }

    /// Where the mini player sits (screen coordinates): right under the notch, inside the grown closed notch.
    public var miniVideoFrame: CGRect? {
        miniVideoSize.map { size in
            CGRect(x: notch.midX - size.width / 2, y: notch.minY - Self.videoPad * 0.75 - size.height,
                   width: size.width, height: size.height)
        }
    }

    private var theaterVideoSize: CGSize? {
        videoAspect.map { atLeastMinimum(CGSize(width: (Self.theaterVideoHeight * $0).rounded(), height: Self.theaterVideoHeight), aspect: $0) }
    }

    /// Where the video sits in theater (screen coordinates): right under the notch, like the mini player.
    public var theaterVideoFrame: CGRect? {
        theaterVideoSize.map { size in
            CGRect(x: notch.midX - size.width / 2, y: notch.minY - Self.videoPad * 0.75 - size.height,
                   width: size.width, height: size.height)
        }
    }

    /// Open with a video: the room left of it for the time and weather, the held apps' two columns, and margins.
    public static let besideVideo: CGFloat = 380

    /// The video's size in the open dropdown.
    public var openVideoSize: CGSize? {
        videoAspect.map { atLeastMinimum(CGSize(width: (Self.openVideoHeight * $0).rounded(), height: Self.openVideoHeight), aspect: $0) }
    }

    /// Grown (keeping its shape) to the smallest the browser allows, so the hole is never smaller than the video.
    private func atLeastMinimum(_ size: CGSize, aspect: CGFloat) -> CGSize {
        guard let minimum = videoMinimum, size.width < minimum.width || size.height < minimum.height else { return size }
        let width = max(minimum.width, minimum.height * aspect).rounded()
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    /// The tab beside the closed notch, starting a little under it so the two read as one shape, and one
    /// point deeper so its bottom edge doesn't sit exactly on the notch's.
    public var tabFrame: CGRect {
        // Against the closed notch's right edge, which is wider than the hardware notch around a mini player.
        let x = notch.midX + size(for: .idle).width / 2 - 8
        let width = 8 + 6 + CGFloat(max(tabSlots, 1)) * Self.tabSlotWidth
        let height = notch.height + 1
        return CGRect(x: x, y: notch.maxY - height, width: width, height: height)
    }

    /// The tab over a tucked video: from where `tabFrame` starts, down over the video with its margin. 8 pt under
    /// the notch, then margin, video, margin, and 8 more so the video sits in the middle of the tab's whole width
    /// (it's drawn in front of the notch, so all of it shows). Held apps' tab stays notch-high, in front of it
    /// along the top, where the tab is beside the notch and the video (below the notch) isn't.
    public var videoTabFrame: CGRect? {
        tuckedVideo.map { tucked in
            let width = 16 + 2 * Self.videoPad + tucked.width
            let height = notch.height + 1 + tucked.height + Self.videoPad
            return CGRect(x: tabFrame.minX, y: notch.maxY - height, width: width, height: height)
        }
    }

    /// How tall a kept caption needs to be to show a whole answer: a rough line count, so it errs tall.
    public static func captionHeight(forAnswerLength characters: Int) -> CGFloat {
        let lines = (characters + 54) / 55
        return min(max(defaultCaptionHeight, 60 + CGFloat(lines) * 22), maxCaptionHeight)
    }

    /// A summary pulls the panel further down than a kept answer, up to this.
    public static let maxSummaryHeight: CGFloat = 420

    /// How tall a summary's caption is: its points, the formula and the chart.
    public static func summaryHeight(for summary: Summary) -> CGFloat {
        let height = 60 + CGFloat(summary.points.count) * 30
            + (summary.formula == nil ? 0 : 50)
            + (summary.bars.isEmpty ? 0 : 110)
        return min(max(defaultCaptionHeight, height), maxSummaryHeight)
    }

    /// The timer rows, then the "TODAY" heading and its rows; 0 when there are none.
    public var agendaHeight: CGFloat {
        guard timerRows + agendaRows > 0 else { return 0 }
        return (agendaRows == 0 ? 0 : Self.agendaHeaderHeight) + CGFloat(timerRows + agendaRows) * Self.agendaRowHeight + Self.agendaGap
    }

    /// The first beat of opening: the notch's width, a little deeper.
    /// With a video held there's no drop beat: the closed notch is already deeper than it.
    public var dropSize: CGSize {
        videoAspect == nil && mediumVideoSize == nil ? CGSize(width: notch.width, height: notch.height + dropDepth) : closedSize
    }

    public func frame(for mode: NotchMode) -> CGRect {
        let size = size(for: mode)
        return CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Where the pointer counts as "on the notch".
    /// Where a tucked video sits: just right of the notch, as high as macOS lets a window go (the menu bar's
    /// bottom), under the side tab, which grows down over it and wears the video icon.
    public var tuckedVideoFrame: CGRect? {
        tuckedVideo.map { CGRect(x: notch.maxX + Self.videoPad, y: notch.minY - $0.height, width: $0.width, height: $0.height) }
    }

    public func hotZone(for mode: NotchMode) -> CGRect {
        // Tucked, the notch and its tab only bring the mini player back (see `VideoController`), never the dropdown.
        if mode != .open, tuckedVideo != nil { return .null }
        // Around a mini player only the hardware notch opens it on hover: over the video, its ↑ ↓ tabs show
        // instead, so it can be watched and controlled without the dropdown jumping open.
        let closed = mode != .open && videoAspect != nil ? notch : frame(for: mode)
        // The tab beside the closed notch opens it too; what's in the tab is in the dropdown as well.
        let frame = mode != .open && showsTab ? closed.union(tabFrame) : closed
        return frame.insetBy(dx: -hoverSlop, dy: -hoverSlop)
    }

    /// Finds the notch from what NSScreen reports. `leftArea`/`rightArea` are
    /// `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`; the notch is the gap between.
    /// Without a notch, returns a small pill at top center of the menu bar.
    public static func notchRect(screenFrame: CGRect, safeAreaTop: CGFloat,
                                 leftArea: CGRect?, rightArea: CGRect?,
                                 menuBarHeight: CGFloat = 24) -> CGRect {
        if safeAreaTop > 0, let left = leftArea, let right = rightArea, right.minX > left.maxX {
            return CGRect(x: left.maxX, y: screenFrame.maxY - safeAreaTop,
                          width: right.minX - left.maxX, height: safeAreaTop)
        }
        let pill = CGSize(width: 180, height: menuBarHeight)
        return CGRect(x: screenFrame.midX - pill.width / 2, y: screenFrame.maxY - pill.height,
                      width: pill.width, height: pill.height)
    }
}
