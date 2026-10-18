import JarvisKit
import Testing

struct NotchStateMachineTests {
    @Test func clickTriggerPeeksOnHoverOpensOnClickClosesOnLeave() {
        var notch = NotchStateMachine(trigger: .click)
        notch.handle(.pointerEntered)
        #expect(notch.mode == .peek)
        notch.handle(.click(inside: true))
        #expect(notch.mode == .open)
        notch.handle(.pointerExited)
        #expect(notch.mode == .idle)
    }

    @Test func peekEndsWhenPointerLeaves() {
        var notch = NotchStateMachine(trigger: .click)
        notch.handle(.pointerEntered)
        notch.handle(.pointerExited)
        #expect(notch.mode == .idle)
    }

    @Test func hoverTriggerOpensAndClosesWithPointer() {
        var notch = NotchStateMachine(trigger: .hover)
        notch.handle(.pointerEntered)
        #expect(notch.mode == .open)
        notch.handle(.click(inside: true))
        notch.handle(.pointerExited)
        #expect(notch.mode == .idle, "clicking inside no longer keeps it open")
    }

    @Test func summonOpensUntilClickOutsideOrDismiss() {
        var notch = NotchStateMachine()
        notch.handle(.summon)
        #expect(notch.mode == .open)
        notch.handle(.click(inside: false))
        #expect(notch.mode == .idle)
        notch.handle(.summon)
        notch.handle(.dismiss)
        #expect(notch.mode == .idle)
    }

    @Test func clickOutsideWhileIdleDoesNothing() {
        var notch = NotchStateMachine()
        notch.handle(.click(inside: false))
        #expect(notch.mode == .idle)
    }
}

struct CaptionHoldTests {
    @Test func heldOpenIgnoresPointerLeavingButNotClickOutsideOrEsc() {
        var notch = NotchStateMachine(trigger: .click)
        notch.handle(.summon)
        notch.holdOpen = true
        notch.handle(.pointerExited)
        #expect(notch.mode == .open, "the caption stays when the pointer moves away")
        notch.handle(.click(inside: false))
        #expect(notch.mode == .idle, "click off still closes")
        notch.handle(.summon)
        notch.handle(.dismiss)
        #expect(notch.mode == .idle)
    }

    @Test func peekStillEndsWhenPointerLeavesEvenIfHeld() {
        var notch = NotchStateMachine(trigger: .click)
        notch.handle(.pointerEntered)
        notch.holdOpen = true
        notch.handle(.pointerExited)
        #expect(notch.mode == .idle)
    }

    @Test func onlyASummonCountsAsSummoned() {
        var machine = NotchStateMachine(trigger: .hover)
        machine.handle(.pointerEntered)
        #expect(machine.mode == .open && !machine.summoned, "hovered open: the pointer, not a summon")
        machine.handle(.summon)
        #expect(!machine.summoned, "already open: still the pointer's")
        machine.handle(.dismiss)
        machine.handle(.summon)
        #expect(machine.mode == .open && machine.summoned)
        machine.handle(.pointerExited)
        #expect(machine.mode == .idle && !machine.summoned)
    }
}
