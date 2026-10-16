import CoreGraphics
import JarvisKit
import Testing

struct VideoLayoutTests {
    let notch = CGRect(x: 660, y: 950, width: 192, height: 32)

    @Test func closedNotchGrowsDownAroundTheMiniPlayer() throws {
        var layout = NotchLayout(notch: notch)
        #expect(layout.miniVideoFrame == nil)
        layout.videoAspect = 16 / 9
        let mini = try #require(layout.miniVideoFrame)
        let closed = layout.frame(for: .idle)
        #expect(closed.width == notch.width + 2 * NotchLayout.miniGrowth, "a little wider than the notch")
        #expect(closed.insetBy(dx: NotchLayout.videoPad - 0.5, dy: 0).contains(mini), "with a margin on each side")
        #expect(mini.width > notch.width, "bigger than before")
        #expect(closed.minY < mini.minY - NotchLayout.videoPad + 1, "and below")
        #expect(abs(mini.width / mini.height - 16 / 9) < 0.02)
    }

    @Test func everyStepOfClosingCoversTheMiniPlayer() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        let mini = try #require(layout.miniVideoFrame)
        // The video moves into the mini spot as soon as closing starts, so every shape on the way must cover it.
        #expect(layout.dropSize == layout.size(for: .idle))
        #expect(layout.frame(for: .open).contains(mini))
        #expect(layout.frame(for: .peek).contains(mini))
    }

    @Test func theOpenDropdownMakesRoomForTheVideo() {
        var layout = NotchLayout(notch: notch)
        let without = layout.size(for: .open).height
        layout.videoAspect = 16 / 9
        #expect(layout.size(for: .open).height == without + NotchLayout.openVideoHeight - 106,
                "the video makes the time row taller")
        #expect(layout.size(for: .open).width >= layout.openVideoSize!.width + 300, "room for the time and the apps strip")
        layout.agendaRows = 5
        let withList = layout.size(for: .open).height
        layout.hidesContent = true
        #expect(layout.size(for: .open).height == withList - layout.agendaHeight, "folded content takes no room")
    }

    @Test func aBrowserMinimumGrowsTheSpotKeepingItsShape() {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        layout.videoMinimum = CGSize(width: 320, height: 180)
        let open = layout.openVideoSize!
        #expect(open.width >= 320 && open.height >= 180)
        #expect(abs(open.width / open.height - 16 / 9) < 0.02)
        #expect(layout.miniVideoFrame!.width >= 320)
    }

    @MainActor @Test func holdingAVideoFoldsTheContentAwayUntilATabIsClicked() {
        let state = AppState()
        state.updateVideo { $0.available = true }
        #expect(state.layout.tabSlots == 1, "a floating video gets a button in the tab")
        state.updateVideo { $0.held = true }
        #expect(state.layout.hidesContent)
        #expect(state.layout.tabSlots == 0)
        state.updateDock { $0.contentHidden = false }
        #expect(!state.layout.hidesContent)
        state.updateVideo { $0.held = false }
        #expect(!state.dock.contentHidden)
    }

    @Test func keepInfoTogglesAndLargeDoesNotChangeIt() {
        #expect(KeepMode.off.next == .on)
        #expect(KeepMode.on.next == .off)
        #expect(KeepMode.large.next == .off)
        var dock = NotchDock()
        dock.keep = .on
        dock.keep = .large
        #expect(dock.keepInfo == .on)
        dock.keep = dock.keepInfo
        #expect(dock.keep == .on)
    }

    @Test func theaterIsJustTheBiggerVideo() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        let normal = layout.size(for: .open)
        layout.theater = true
        let video = try #require(layout.theaterVideoFrame)
        let open = layout.frame(for: .open)
        #expect(video.height == NotchLayout.theaterVideoHeight)
        #expect(video.height > layout.openVideoSize!.height, "bigger than in the normal dropdown")
        #expect(open.contains(video))
        #expect(open.width < normal.width + 1 || open.height != normal.height, "a different shape from the dropdown")
        #expect(open.height - video.height - notch.height < 3 * NotchLayout.videoPad, "nothing but the video and its frame")
    }

    @Test func hoveringTheMiniPlayerDoesntOpenTheNotch() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        let mini = try #require(layout.miniVideoFrame)
        #expect(!layout.hotZone(for: .idle).contains(CGPoint(x: mini.midX, y: mini.midY)), "over the video: tabs, not the dropdown")
        #expect(layout.hotZone(for: .idle).contains(CGPoint(x: notch.midX, y: notch.midY)), "the hardware notch still opens it")
    }

    @Test func miniAndLargeShareConcentricCorners() {
        #expect(NotchLayout.videoCornerRadius == NotchLayout.videoHoleRadius + NotchLayout.videoHoleInset + NotchLayout.videoPad)
    }

    @MainActor @Test func aTuckedVideoLeavesThePlainNotchAndAnIcon() {
        let state = AppState()
        state.updateVideo { $0.held = true }
        #expect(state.layout.videoAspect != nil)
        state.updateVideo { $0.tucked = true }
        #expect(state.layout.videoAspect == nil, "the notch closes up plain")
        #expect(state.layout.tabSlots == 1, "an icon to bring it back")
    }

    @Test func aTuckedVideoWaitsRightOfTheNotchUnderTheTab() throws {
        var layout = NotchLayout(notch: notch)
        layout.tuckedVideo = CGSize(width: 59, height: 33)
        let video = try #require(layout.tuckedVideoFrame)
        #expect(layout.frame(for: .idle) == notch, "the notch itself stays plain")
        #expect(video.minX > notch.maxX, "right of the notch")
        #expect(video.maxY == notch.minY, "as high as a window may go")
        #expect(layout.tabFrame.contains(video), "the side tab grows down over it")
        #expect(layout.hotZone(for: .idle).isNull, "hovering brings the video back rather than opening the dropdown")
    }

    @Test func switchingToLargeTheDropdownIsAsDeepAsLarge() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        layout.tallForTheater = true
        let big = try #require(layout.theaterVideoFrame)
        #expect(layout.frame(for: .open).contains(big), "the big video fits inside the full-width dropdown mid-switch")
    }
}

