import CoreGraphics
import Foundation
import JarvisKit
import Testing

struct NotchDockTests {
    let notch = CGRect(x: 660, y: 950, width: 192, height: 32)

    @Test func catchesCloseButOnlyLetsGoFurtherOut() {
        var dock = DockCatch()
        var changed = dock.update(pointer: CGPoint(x: 756, y: 920), catchIn: notch, releaseOutside: notch)
        #expect(!changed, "30 pt below: not yet")
        changed = dock.update(pointer: CGPoint(x: 756, y: 945), catchIn: notch, releaseOutside: notch)
        #expect(changed && dock.caught)
        changed = dock.update(pointer: CGPoint(x: 756, y: 920), catchIn: notch, releaseOutside: notch)
        #expect(!changed, "back out 30 pt: still caught")
        changed = dock.update(pointer: CGPoint(x: 756, y: 850), catchIn: notch, releaseOutside: notch)
        #expect(changed)
        #expect(!dock.caught)
    }

    @Test func aDraggedWindowKeepsTheDropdownOpenAnywhereOverIt() {
        var layout = NotchLayout(notch: notch)
        layout.showsShelf = true
        let dropdown = layout.frame(for: .open)
        var opener = DockCatch()
        opener.update(pointer: CGPoint(x: notch.midX, y: notch.midY), catchIn: notch, releaseOutside: dropdown)
        #expect(opener.caught)
        // Down at the drop box, far below the notch itself.
        opener.update(pointer: CGPoint(x: notch.midX, y: dropdown.minY + 40), catchIn: notch, releaseOutside: dropdown)
        #expect(opener.caught)
        opener.update(pointer: CGPoint(x: notch.midX, y: dropdown.minY - 200), catchIn: notch, releaseOutside: dropdown)
        #expect(!opener.caught)
    }

    @Test func theBoxHasItsOwnTighterMargins() {
        let box = CGRect(x: 600, y: 800, width: 300, height: 100)
        var catcher = DockCatch(catchMargin: 16, releaseMargin: 40)
        catcher.update(pointer: CGPoint(x: 750, y: 780), catchIn: box, releaseOutside: box)
        #expect(!catcher.caught, "20 pt below the box: not yet")
        catcher.update(pointer: CGPoint(x: 750, y: 790), catchIn: box, releaseOutside: box)
        #expect(catcher.caught)
        catcher.update(pointer: CGPoint(x: 750, y: 770), catchIn: box, releaseOutside: box)
        #expect(catcher.caught, "30 pt out: still caught")
        catcher.update(pointer: CGPoint(x: 750, y: 750), catchIn: box, releaseOutside: box)
        #expect(!catcher.caught)
    }

    @Test func otherTabsAndTheDropBoxUseTheShelfsHeight() {
        var layout = NotchLayout(notch: notch)
        layout.agendaRows = 8
        let withList = layout.size(for: .open).height
        layout.showsShelf = true
        #expect(layout.size(for: .open).height == NotchLayout(notch: notch).size(for: .open).height + NotchLayout.shelfHeight)
        #expect(layout.size(for: .open).height != withList)
        layout.showsCaption = true
        #expect(layout.size(for: .open).height == NotchLayout(notch: notch).size(for: .open).height + layout.captionHeight,
                "a caption still wins")
    }

    @Test func tabIsOnePointDeeperThanTheNotchAndGrowsWithItsIcons() {
        var layout = NotchLayout(notch: notch)
        layout.tabSlots = 1
        let one = layout.tabFrame
        #expect(one.maxY == notch.maxY)
        #expect(one.height == notch.height + 1)
        #expect(one.minX < notch.maxX, "starts under the notch")
        layout.tabSlots = 3
        #expect(layout.tabFrame.width == one.width + 2 * NotchLayout.tabSlotWidth)
        #expect(layout.hotZone(for: .idle).contains(CGPoint(x: layout.tabFrame.maxX - 4, y: 965)),
                "hovering the tab opens the notch")
        layout.tabSlots = 0
        #expect(!layout.hotZone(for: .idle).contains(CGPoint(x: layout.tabFrame.maxX - 4, y: 965)),
                "but not where there's no tab")
    }

    @MainActor @Test func tabsAndDraggingDriveTheLayout() {
        let state = AppState()
        #expect(!state.layout.showsShelf, "Today uses the list's own height")
        state.updateDock { $0.dragging = .app }
        #expect(state.layout.showsShelf)
        #expect(state.notch.openOnHover)
        state.updateDock { $0.dragging = nil; $0.tab = .monitor }
        #expect(state.layout.showsShelf)
        state.updateDock { $0.apps = (1...6).map { HeldApp(pid: $0, appName: "App") } }
        #expect(state.layout.tabSlots == 6)
        #expect(state.dock.isFull)
    }

    @MainActor @Test func keepLocksOnEveryTab() {
        for tab in PanelTab.allCases {
            let state = AppState()
            state.updateDock { $0.tab = tab; $0.keep = .on }
            state.send(.summon)
            state.send(.click(inside: false))
            #expect(state.notch.mode == .open, "Keep holds \(tab) open")
            state.updateDock { $0.keep = .off }
            state.send(.click(inside: false))
            #expect(state.notch.mode == .idle, "and lets go once it's off")
        }
    }

    @Test func lockedNotchOnlyClosesOnDismiss() {
        var machine = NotchStateMachine(trigger: .click)
        machine.handle(.summon)
        machine.locked = true
        machine.handle(.pointerExited)
        machine.handle(.click(inside: false))
        #expect(machine.mode == .open)
        machine.handle(.dismiss)
        #expect(machine.mode == .idle)
    }

    @Test func openOnHoverSkipsThePeek() {
        var machine = NotchStateMachine(trigger: .click)
        machine.openOnHover = true
        machine.handle(.pointerEntered)
        #expect(machine.mode == .open)
    }

    @Test func screenFlipIsItsOwnInverse() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(ScreenSpace.flip(ScreenSpace.flip(rect, mainHeight: 982), mainHeight: 982) == rect)
        #expect(ScreenSpace.flip(rect, mainHeight: 982).minY == CGFloat(982 - 220))
    }

    @MainActor @Test func eachDesktopHasItsOwnStripAndSameAppWindowsAreNumbered() {
        let state = AppState()
        let notes1 = HeldApp(pid: 7, appName: "Notes", desktop: 1), notes2 = HeldApp(pid: 7, appName: "Notes", desktop: 1)
        let mail = HeldApp(pid: 8, appName: "Mail", desktop: 2)
        state.updateDock { $0.desktop = 1; $0.apps = [notes1, mail, notes2] }
        #expect(state.dock.shownApps.map(\.id) == [notes1.id, notes2.id])
        #expect(state.layout.tabSlots == 2)
        #expect(state.dock.number(of: notes1) == 1 && state.dock.number(of: notes2) == 2)
        state.updateDock { $0.desktop = 2 }
        #expect(state.dock.shownApps.map(\.id) == [mail.id])
        #expect(state.dock.number(of: mail) == nil, "one window of an app gets no number")
    }

    @MainActor @Test func keepHoldsTheDropdownWithAVideoToo() {
        let state = AppState()
        state.updateDock { $0.keep = .on }
        state.updateVideo { $0.held = true }
        state.send(.summon)
        state.send(.click(inside: false))
        #expect(state.notch.mode == .open)
    }
}
