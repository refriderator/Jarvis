import SwiftUI

/// Moving the notch to another display: it dips, rises off the top of the display it leaves, the panel moves while
/// it's out of sight, and it drops onto the new one with a bounce. The panel can't be animated across displays
/// itself (it would sweep over everything between), so the notch is drawn higher and higher inside it instead,
/// and the panel's top edge (the screen's) hides it. It never goes lower than at rest: the dip and the bounce
/// stretch it from its top edge instead, since moved down, the display's top edge showed above it.
///
/// Only where there's no hardware notch. On a display with one, the closed notch is drawn as that notch and the
/// tabs beside it hang from it, so rising or stretching looked like the hardware notch (or the tabs' base under
/// it) moving: there the tabs slide in behind the notch instead (`tabsTucked`) and spring out on arrival.
@MainActor
@Observable
final class NotchHop {
    /// How far up the notch is drawn: 0 at rest, never below.
    private(set) var lift: CGFloat = 0
    /// How much taller it's drawn, from its top edge: 1 at rest.
    private(set) var stretch: CGFloat = 1
    /// Tabs beside a hardware notch are in behind it.
    private(set) var tabsTucked = false
    @ObservationIgnored private var hops = 0

    /// The whole move. `height` is how tall the notch is and `rises` whether it rises (and stretches) rather than
    /// tucking its tabs in (no hardware notch), both read before and after the move, since they can differ on the
    /// new display; `move` puts the panel on the new display, and runs while the notch is out of sight.
    func hop(height: @escaping () -> CGFloat, rises: @escaping () -> Bool, move: @escaping () -> Void) {
        let current = leave(height: height(), rises: rises(), springy: rises())
        after(Self.away, current) {
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            withTransaction(instant, move)
            self.arrive(height: height, rises: rises, springy: rises)
        }
    }

    /// How long leaving takes, until it's out of sight.
    static let away = 0.34

    /// Dips, then rises out of sight (`springy`: the dip is a stretch); or, not rising, tucks the tabs in. Returns
    /// the hop's number, which a later hop makes stale.
    @discardableResult
    func leave(height: CGFloat, rises: Bool, springy: Bool) -> Int {
        hops += 1
        let current = hops
        guard rises else {
            tabsTucked = true
            return current
        }
        let height = max(height, 1)
        if springy { withAnimation(.easeOut(duration: 0.1)) { stretch = 1 + 6 / height } }
        after(0.1, current) {
            withAnimation(.easeIn(duration: 0.22)) {
                self.stretch = 1
                self.lift = height + 30
            }
        }
        return current
    }

    /// From out of sight (at once), drops in, then bounces: its bottom springing down and back. Not rising: from
    /// tucked in, the tabs spring out.
    func arrive(height: @escaping () -> CGFloat, rises: @escaping () -> Bool, springy: @escaping () -> Bool) {
        hops += 1
        let current = hops
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        guard rises() else {
            withTransaction(instant) {
                stretch = 1
                lift = 0
                tabsTucked = true
            }
            after(0.06, current) { self.tabsTucked = false }
            return
        }
        withTransaction(instant) {
            stretch = 1
            lift = max(height(), 1) + 30
            tabsTucked = false
        }
        after(0.06, current) { withAnimation(.easeOut(duration: 0.26)) { self.lift = 0 } }
        after(0.3, current) {
            guard springy() else { return }
            withAnimation(.easeOut(duration: 0.07)) { self.stretch = 1 + 8 / max(height(), 1) }
        }
        after(0.37, current) { withAnimation(.spring(duration: 0.45, bounce: 0.5)) { self.stretch = 1 } }
    }

    private func after(_ delay: Double, _ hop: Int, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, hop == self.hops else { return }
            work()
        }
    }
}

extension EnvironmentValues {
    /// Tabs beside a hardware notch slide in behind it (`NotchHop.tabsTucked`).
    @Entry var tabsTucked = false
}

/// Draws `content` as high (and as stretched) as the hop has it. Read in a body, so it follows the hop.
struct Hopping<Content: View>: View {
    let hop: NotchHop
    let content: Content

    var body: some View {
        content
            .scaleEffect(x: 1, y: hop.stretch, anchor: .top)
            .offset(y: -hop.lift)
            .environment(\.tabsTucked, hop.tabsTucked)
    }
}
