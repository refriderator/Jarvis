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
        state.updateVideo { $0.tucked = true; $0.tuckedSize = CGSize(width: 59, height: 33) }
        #expect(state.layout.videoAspect == nil, "the notch closes up plain")
        #expect(state.layout.tabSlots == 0, "no slot among the apps: it has its own tab")
        #expect(state.layout.videoTabFrame != nil, "a tab to bring it back")
    }

    @Test func aTuckedVideoWaitsRightOfTheNotchUnderTheTab() throws {
        var layout = NotchLayout(notch: notch)
        layout.tuckedVideo = CGSize(width: 59, height: 33)
        let video = try #require(layout.tuckedVideoFrame)
        #expect(layout.frame(for: .idle) == notch, "the notch itself stays plain")
        #expect(video.minX > notch.maxX, "right of the notch")
        #expect(video.maxY == notch.minY, "as high as a window may go")
        #expect(try #require(layout.videoTabFrame).contains(video), "its tab grows down over it")
        #expect(layout.hotZone(for: .idle).isNull, "hovering brings the video back rather than opening the dropdown")
    }

    @Test func switchingToLargeTheDropdownIsAsDeepAsLarge() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        layout.tallForTheater = true
        let big = try #require(layout.theaterVideoFrame)
        #expect(layout.frame(for: .open).contains(big), "the big video fits inside the full-width dropdown mid-switch")
    }

    @Test func heldAppsSitAlongTheTopOfATuckedVideosTab() throws {
        var layout = NotchLayout(notch: notch)
        layout.tuckedVideo = CGSize(width: 59, height: 33)
        layout.tabSlots = 3
        let apps = layout.tabFrame, tab = try #require(layout.videoTabFrame)
        let video = try #require(layout.tuckedVideoFrame)
        #expect(apps.height == notch.height + 1, "the apps' tab stays notch-high")
        #expect(apps.minX == tab.minX && apps.maxY == tab.maxY, "from the same corner, in front along the top")
        // Its bottom edge is a point below the notch's, so it laps the video's top edge by that point, no more.
        #expect(apps.minY >= video.maxY - 1, "so the icons never sit on the video or its icon")
        #expect(tab.contains(video))
    }

    @Test func aVideoFillingAnyDisplayIsFullScreen() {
        let main = CGRect(x: 0, y: 0, width: 2080, height: 1170)
        let external = CGRect(x: -2560, y: -300, width: 2560, height: 1440)
        let screens = [main, external]
        #expect(VideoDock.fillsScreen(main, screens: screens), "full screen on the Mac's own display")
        #expect(VideoDock.fillsScreen(external.insetBy(dx: 0, dy: 40), screens: screens), "on the external one, menu bar and all")
        #expect(!VideoDock.fillsScreen(CGRect(x: 800, y: 900, width: 480, height: 270), screens: screens), "Large is not full screen")
        #expect(!VideoDock.fillsScreen(CGRect(x: 900, y: 1040, width: 220, height: 124), screens: screens), "nor the mini player")
    }
}
