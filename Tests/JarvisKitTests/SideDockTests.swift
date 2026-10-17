import CoreGraphics
import Foundation
import JarvisKit
import Testing

struct SideDockTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func aDisplayAgainstAnEdgeTakesThatSideAway() {
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        #expect(SideDock.freeSides(of: screen, others: [screen]) == [.left, .right])
        #expect(SideDock.freeSides(of: screen, others: [screen, external]) == [.left])
        #expect(SideDock.freeSides(of: external, others: [screen, external]) == [.right])
    }

    @Test func goesToTheNearerFreeSide() {
        let leftish = CGRect(x: 100, y: 200, width: 600, height: 400)
        #expect(SideDock.side(for: leftish, on: screen, free: [.left, .right]) == .left)
        #expect(SideDock.side(for: leftish, on: screen, free: [.right]) == .right)
        #expect(SideDock.side(for: leftish, on: screen, free: []) == nil)
    }

    @Test func parkedLeavesASliverAndKeepsItsSize() {
        let frame = CGRect(x: 300, y: 200, width: 800, height: 600)
        let left = SideDock.parked(frame, side: .left, screen: screen, visible: visible)
        #expect(left.maxX == SideDock.sliver)
        #expect(left.size == frame.size)
        #expect(left.minY == 200)
        let right = SideDock.parked(frame, side: .right, screen: screen, visible: visible)
        #expect(right.minX == screen.maxX - SideDock.sliver)
    }

    @Test func parkedStaysBelowTheMenuBar() {
        let tall = CGRect(x: 0, y: 100, width: 800, height: 900)
        let parked = SideDock.parked(tall, side: .left, screen: screen, visible: visible)
        #expect(parked.maxY == visible.maxY)
    }

    @Test func cardsStackDownTheEdgeAndHideOffIt() {
        let shown = SideDock.cards(count: 3, side: .left, visible: visible, showing: true)
        #expect(shown.count == 3)
        #expect(shown.allSatisfy { $0.minX == SideDock.cardInset })
        #expect(zip(shown, shown.dropFirst()).allSatisfy { $0.minY > $1.maxY }, "top to bottom, not overlapping")
        let hidden = SideDock.cards(count: 3, side: .right, visible: visible, showing: false)
        #expect(hidden.allSatisfy { $0.minX >= visible.maxX })
        let many = SideDock.cards(count: 6, side: .left, visible: CGRect(x: 0, y: 0, width: 1000, height: 600), showing: true)
        #expect(many.first!.maxY <= 600 && many.last!.minY >= 0, "shrunk to fit")
    }

    @Test func edgeOnlyBetweenMenuBarAndDock() {
        #expect(SideDock.atEdge(CGPoint(x: 1, y: 500), side: .left, screen: screen, visible: visible))
        #expect(!SideDock.atEdge(CGPoint(x: 1, y: 970), side: .left, screen: screen, visible: visible))
        #expect(SideDock.atEdge(CGPoint(x: 1511, y: 500), side: .right, screen: screen, visible: visible))
        #expect(!SideDock.atEdge(CGPoint(x: 800, y: 500), side: .right, screen: screen, visible: visible))
    }

    @Test func droppedAtAFreeEdgeGoesThere() {
        #expect(SideDock.dropSide(CGPoint(x: 5, y: 500), screen: screen, visible: visible, free: [.left, .right]) == .left)
        #expect(SideDock.dropSide(CGPoint(x: 1508, y: 500), screen: screen, visible: visible, free: [.left, .right]) == .right)
        #expect(SideDock.dropSide(CGPoint(x: 5, y: 500), screen: screen, visible: visible, free: [.right]) == nil)
        #expect(SideDock.dropSide(CGPoint(x: 700, y: 500), screen: screen, visible: visible, free: [.left, .right]) == nil)
    }

    @Test func aDraggedCardLandsOnTheHalfAndSlotUnderThePointer() {
        let none: (ScreenSide) -> Int = { _ in 0 }
        let two: (ScreenSide) -> Int = { _ in 2 }
        #expect(SideDock.cardDrop(CGPoint(x: 200, y: 500), screen: screen, visible: visible, free: [.left, .right], count: none)! == (.left, 0))
        #expect(SideDock.cardDrop(CGPoint(x: 1300, y: 500), screen: screen, visible: visible, free: [.left], count: none)! == (.left, 0),
                "that half's side isn't free")
        let slots = SideDock.cards(count: 3, side: .right, visible: visible, showing: true)
        #expect(SideDock.cardDrop(CGPoint(x: 1300, y: slots[0].midY), screen: screen, visible: visible, free: [.left, .right], count: two)! == (.right, 0))
        #expect(SideDock.cardDrop(CGPoint(x: 1300, y: slots[2].midY), screen: screen, visible: visible, free: [.left, .right], count: two)! == (.right, 2))
        #expect(SideDock.cardDrop(CGPoint(x: 1300, y: 2), screen: screen, visible: visible, free: [.left, .right], count: two)! == (.right, 2))
        #expect(SideDock.cardDrop(CGPoint(x: 1300, y: 500), screen: screen, visible: visible, free: [], count: two) == nil)
    }

    @Test func aPoppedWindowIsAboutSystemSettingsSizedAndAllOnScreen() {
        let right = SideDock.popped(side: .right, visible: visible)
        #expect(right.size == SideDock.popSize)
        #expect(right.maxX == visible.maxX - SideDock.popInset)
        #expect(visible.contains(right))
        let small = CGRect(x: 0, y: 0, width: 600, height: 500)
        #expect(small.contains(SideDock.popped(side: .left, visible: small)))
    }

    @Test func aPoppedWindowComesBackAtTheSizeItWasLeftAt() {
        let resized = SideDock.popped(CGSize(width: 900, height: 500), side: .left, visible: visible)
        #expect(resized.size == CGSize(width: 900, height: 500))
        #expect(resized.minX == visible.minX + SideDock.popInset)
        // Too big for the display: shrunk to fit, still all on it.
        #expect(visible.contains(SideDock.popped(CGSize(width: 3000, height: 3000), side: .right, visible: visible)))
    }

    @Test func theMiddleThirdLetsGoAtTheWindowsSizeCentred() {
        #expect(SideDock.inMiddle(CGPoint(x: screen.midX, y: 400), screen: screen))
        #expect(!SideDock.inMiddle(CGPoint(x: screen.width * 0.2, y: 400), screen: screen))
        #expect(!SideDock.inMiddle(CGPoint(x: screen.width * 0.8, y: 400), screen: screen))
        let frame = SideDock.released(CGSize(width: 800, height: 600), visible: visible)
        #expect(frame.size == CGSize(width: 800, height: 600))
        #expect(abs(frame.midX - visible.midX) <= 1 && abs(frame.midY - visible.midY) <= 1)
        #expect(visible.contains(SideDock.released(CGSize(width: 4000, height: 3000), visible: visible)))
    }

    @Test func aWindowBiggerThanAskedIsMovedOnScreen() {
        // An app with a 1100 pt minimum width, placed for 720 from the right edge: half of it was off screen.
        let got = CGRect(x: visible.maxX - 730, y: 100, width: 1100, height: 900)
        let fixed = SideDock.onScreen(got, side: .right, visible: visible)
        #expect(fixed.size == got.size)
        #expect(visible.contains(fixed))
    }

    @Test func wideWindowsStayWithTheirDisplay() {
        // A laptop below and left of the main display: a wide window off the main one's left edge would sit nearer
        // the laptop, and macOS would give it the laptop's desktop.
        let main = CGRect(x: 0, y: 0, width: 2080, height: 1170)
        let laptop = CGRect(x: -1049, y: -828, width: 1280, height: 828)
        let mainVisible = CGRect(x: 0, y: 0, width: 2080, height: 1140)
        let wide = SideDock.parked(CGRect(x: 100, y: 0, width: 1769, height: 1140), side: .left, screen: main,
                                   visible: mainVisible, others: [laptop])
        #expect(wide.width < 1769)
        #expect(wide.maxX == main.minX + SideDock.sliver)
        #expect(SideDock.nearest(to: wide, among: [main, laptop]) == main)
        // Nothing near: it keeps its width.
        let alone = SideDock.parked(CGRect(x: 100, y: 0, width: 1769, height: 1140), side: .left, screen: main,
                                    visible: mainVisible)
        #expect(alone.width == 1769)
    }
}

struct TrayLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 2080, height: 1170)

    @Test func withoutANotchItHangsFromTheMiddleAndOpensDown() {
        let layout = TrayLayout(screen: screen, menuBarHeight: 30)
        let dot = layout.frame(for: .dot), open = layout.frame(for: .open)
        #expect(dot.midX == screen.midX && dot.maxY == screen.maxY && dot.height == 30)
        #expect(open.midX == screen.midX && open.maxY == screen.maxY)
        #expect(open.width > dot.width * 2 && open.height > dot.height * 3)
        #expect(layout.frame(for: .hidden).height == 0)
        #expect(layout.approachZone.contains(CGPoint(x: screen.midX + 200, y: screen.maxY - 20)))
        #expect(layout.dropZone.contains(open))
    }

    @Test func besideAHardwareNotchItSlidesOutSideways() {
        let notch = CGRect(x: 1000, y: 1138, width: 180, height: 32)
        let layout = TrayLayout(screen: screen, menuBarHeight: 32, hardwareNotch: notch)
        #expect(layout.frame(for: .hidden) == notch)
        for stage in [TrayStage.dot, .open] {
            let frame = layout.frame(for: stage)
            #expect(frame.minX == notch.minX && frame.minY == notch.minY && frame.height == notch.height)
            #expect(frame.maxX > notch.maxX)
        }
        #expect(layout.frame(for: .open).width > layout.frame(for: .dot).width)
    }
}
