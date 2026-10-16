import CoreGraphics
import JarvisKit
import Testing

struct NotchLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func findsNotchBetweenAuxiliaryAreas() {
        let notch = NotchLayout.notchRect(
            screenFrame: screen, safeAreaTop: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32))
        #expect(notch == CGRect(x: 660, y: 950, width: 192, height: 32))
    }

    @Test func fallsBackToCenteredPillWithoutNotch() {
        let pill = NotchLayout.notchRect(screenFrame: screen, safeAreaTop: 0,
                                         leftArea: nil, rightArea: nil, menuBarHeight: 24)
        #expect(pill.midX == screen.midX)
        #expect(pill.maxY == screen.maxY)
        #expect(pill.height == 24)
    }

    @Test func everyModeHangsFromTheNotchTopAndStaysCentered() {
        let layout = NotchLayout(notch: CGRect(x: 660, y: 950, width: 192, height: 32))
        for mode in [NotchMode.idle, .peek, .open] {
            let frame = layout.frame(for: mode)
            #expect(frame.maxY == 982)
            #expect(frame.midX == 756)
        }
        #expect(layout.frame(for: .idle) == layout.notch)
        #expect(layout.size(for: .peek).width > layout.notch.width)
        #expect(layout.size(for: .open).height > layout.size(for: .peek).height)
    }

    @Test func hotZoneIsSlightlyBiggerThanFrame() {
        let layout = NotchLayout(notch: CGRect(x: 660, y: 950, width: 192, height: 32))
        #expect(layout.hotZone(for: .idle).contains(CGPoint(x: 658, y: 960)))
    }
}

struct MediumPlayerTests {
    private let notch = CGRect(x: 600, y: 950, width: 185, height: 32)

    @Test func aLittleBiggerThanTheMiniPlayerAndPeeksDown() throws {
        var layout = NotchLayout(notch: notch)
        layout.videoAspect = 16 / 9
        let mini = layout.size(for: .idle)
        layout.videoAspect = nil
        layout.browserMini = true
        let medium = layout.size(for: .idle)
        #expect(medium.width > mini.width && medium.width < mini.width + 80)
        #expect(medium.height > mini.height)
        let peek = layout.size(for: .peek)
        #expect(peek.height == medium.height + NotchLayout.mediumPeek.height, "hovering drops it down a little")
        #expect(layout.dropSize == medium, "no drop beat: it's already deeper")
    }

    @Test func aHeldVideosMiniPlayerWins() {
        var layout = NotchLayout(notch: notch)
        layout.browserMini = true
        layout.videoAspect = 16 / 9
        #expect(layout.mediumVideoSize == nil)
    }
}

@MainActor
struct BrowserMiniTests {
    @Test func onlyWhileTheWebTabShows() {
        let state = AppState()
        state.updateDock { $0.tab = .browser; $0.browserFullscreen = true }
        #expect(state.layout.browserMini)
        state.updateDock { $0.contentHidden = true }
        #expect(!state.layout.browserMini, "the Web tab folded away")
        state.updateDock { $0.contentHidden = false; $0.tab = .today }
        #expect(!state.layout.browserMini, "another tab showing")
    }
}
