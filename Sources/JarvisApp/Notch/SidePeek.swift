import AppKit
import JarvisKit
import Observation
import ScreenCaptureKit
import SwiftUI

/// The cards that slide out of a screen edge for the windows held there (`SideDockController`), like Stage
/// Manager's strip. macOS gives no way to shrink another app's window or show it above the one in front without
/// focusing it, so the cards are Jarvis's own: a live picture of each window when Jarvis may record the screen,
/// otherwise its app's icon and title.
@MainActor
final class SidePeek {
    /// A card was clicked.
    var onPick: (UUID) -> Void = { _ in }
    /// A card started being dragged.
    var onDrag: (UUID) -> Void = { _ in }
    /// A card's × (or "Let Go" in its menu): its window stops being held.
    var onLetGo: (UUID) -> Void = { _ in }
    /// The cards' frames on screen while they show (screen coordinates).
    private(set) var area: CGRect = .zero

    private let state: AppState
    private let panel = NotchPanel()
    private let model = SidePeekModel()
    private lazy var ghost = CardGhost(skin: { [state] in state.skin })
    private var frames: [(id: UUID, frame: CGRect)] = []
    private var refresher: Timer?
    /// The windows the cards showing are for, pictured again every second.
    private var capturing: [ParkedWindow] = []
    /// Room around the cards for their shadow.
    private static let margin: CGFloat = 14

    init(state: AppState) {
        self.state = state
        panel.level = .mainMenu + 2
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: SidePeekView(model: model, skin: { state.skin },
                                                                 pick: { [weak self] id in self?.onPick(id) },
                                                                 drag: { [weak self] id in self?.onDrag(id) },
                                                                 letGo: { [weak self] id in self?.onLetGo(id) }))
    }

    /// Slides the cards for `items` out of `side`; with `animated` off they're just put there (while a card is
    /// dragged over them). The `placeholder` card is an empty slot: where the dragged card would land.
    func show(_ items: [ParkedWindow], side: ScreenSide, on screen: NSScreen, placeholder: UUID? = nil,
              animated: Bool = true) {
        let shown = SideDock.cards(count: items.count, side: side, visible: screen.visibleFrame, showing: true)
        let hidden = SideDock.cards(count: items.count, side: side, visible: screen.visibleFrame, showing: false)
        guard let first = shown.first, let last = shown.last else { return }
        area = first.union(last)
        frames = zip(items, shown).map { ($0.id, $1) }
        model.cardHeight = first.height
        model.cards = items.map { item in
            let app = NSRunningApplication(processIdentifier: item.window.pid)
            return SidePeekModel.Card(id: item.id, icon: app?.icon, name: app?.localizedName ?? "App",
                                      title: Self.title(of: item.window), image: model.images[item.id])
        }
        model.highlighted = nil
        model.placeholder = placeholder
        let outer = area.insetBy(dx: -Self.margin, dy: -Self.margin)
        panel.ignoresMouseEvents = false
        guard animated else {
            panel.setFrame(outer, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        let start = outer.offsetBy(dx: hidden[0].minX - first.minX, dy: 0)
        panel.setFrame(start, display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(outer, display: true)
            panel.animator().alphaValue = 1
        }
        capturing = items
        capture()
        refresher?.invalidate()
        refresher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        }
    }

    func hide() {
        refresher?.invalidate()
        refresher = nil
        capturing = []
        frames = []
        area = .zero
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }
    }

    /// The card under a point on screen.
    func card(at point: CGPoint) -> (id: UUID, frame: CGRect)? {
        frames.first { $0.frame.contains(point) }
    }

    func highlight(_ id: UUID?) {
        if model.highlighted != id { model.highlighted = id }
    }

    /// The card lifts off into the pointer, held where it was grabbed, and follows it.
    func lift(_ id: UUID) {
        guard let card = model.cards.first(where: { $0.id == id }),
              let frame = frames.first(where: { $0.id == id })?.frame else { return }
        let pointer = NSEvent.mouseLocation
        ghost.lift(card, size: frame.size, grab: CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY))
    }

    func dropGhost() {
        ghost.hide()
    }

    // MARK: Pictures

    /// Live pictures of the windows, with Screen Recording allowed (never asked for here: Settings has the button).
    private func capture() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = capturing.compactMap { item in Desktops.windowID(of: item.window.element).map { (item.id, $0) } }
        let height = model.cardHeight
        Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            for (id, windowID) in ids {
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else { continue }
                let config = SCStreamConfiguration()
                let scale = 2 * height / max(window.frame.height, 1)
                config.width = Int(window.frame.width * scale)
                config.height = Int(window.frame.height * scale)
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: window)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                else { continue }
                await MainActor.run { self?.model.setImage(image, for: id) }
            }
        }
    }

    private static func title(of window: ForeignWindow) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window.element, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }
}

@MainActor
@Observable
final class SidePeekModel {
    struct Card: Identifiable {
        let id: UUID
        let icon: NSImage?
        let name: String
        let title: String
        var image: CGImage?
    }

    var cards: [Card] = []
    var highlighted: UUID?
    /// The dragged card's slot, drawn empty.
    var placeholder: UUID?
    var cardHeight: CGFloat = SideDock.cardHeight
    /// The last picture of each window, so cards show it straight away next time.
    @ObservationIgnored var images: [UUID: CGImage] = [:]

    func setImage(_ image: CGImage, for id: UUID) {
        images[id] = image
        if let index = cards.firstIndex(where: { $0.id == id }) { cards[index].image = image }
    }
}

private struct SidePeekView: View {
    let model: SidePeekModel
    let skin: () -> Skin
    let pick: (UUID) -> Void
    let drag: (UUID) -> Void
    let letGo: (UUID) -> Void

    var body: some View {
        let skin = skin()
        VStack(spacing: SideDock.cardGap) {
            ForEach(model.cards) { card in
                Group {
                    if model.placeholder == card.id {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(skin.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    } else {
                        SidePeekCard(card: card, skin: skin, highlighted: model.highlighted == card.id)
                            .overlay(alignment: .topTrailing) {
                                // On the hovered card: stop holding it, the window going back where it was.
                                if model.highlighted == card.id {
                                    Button { letGo(card.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(skin.foreground, skin.background.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .help("Let go: put the window back where it was")
                                    .transition(.opacity)
                                }
                            }
                    }
                }
                .frame(width: SideDock.cardWidth, height: model.cardHeight)
                .contentShape(Rectangle())
                .onTapGesture { pick(card.id) }
                .contextMenu { Button("Let Go") { letGo(card.id) } }
                // Only the start: `SideDockController` follows the pointer from there.
                .gesture(DragGesture(minimumDistance: 4).onChanged { _ in
                    if model.placeholder == nil { drag(card.id) }
                })
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidePeekCard: View {
    let card: SidePeekModel.Card
    let skin: Skin
    let highlighted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            if let image = card.image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    if let icon = card.icon {
                        Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                    }
                    Text(card.title.isEmpty ? card.name : card.title)
                        .font(.system(size: 11, weight: .medium))
                        .fontDesign(skin.fontDesign)
                        .foregroundStyle(skin.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if card.image != nil, let icon = card.icon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26).padding(6)
            }
        }
        .background(skin.background.opacity(0.88), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(highlighted ? skin.accent : (skin.border ?? skin.accent.opacity(0.35)),
                                    lineWidth: highlighted ? 2 : 1))
        .scaleEffect(highlighted ? 1.04 : 1)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}

/// A card held in the pointer while it's dragged to another place or side, drawn above everything.
@MainActor
final class CardGhost {
    private let skin: () -> Skin
    private var tracker: Timer?
    private var grab: CGPoint = .zero
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 4
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }()

    init(skin: @escaping () -> Skin) {
        self.skin = skin
    }

    func lift(_ card: SidePeekModel.Card, size: CGSize, grab: CGPoint) {
        self.grab = grab
        // Room for the shadow and the lift's slight swell.
        let pad: CGFloat = 16
        panel.contentView = NSHostingView(rootView: SidePeekCard(card: card, skin: skin(), highlighted: true)
            .frame(width: size.width, height: size.height)
            .padding(pad)
            .rotationEffect(.degrees(-2)))
        panel.setContentSize(CGSize(width: size.width + pad * 2, height: size.height + pad * 2))
        follow()
        panel.alphaValue = 0.92
        panel.orderFrontRegardless()
        tracker?.invalidate()
        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    func hide() {
        tracker?.invalidate()
        tracker = nil
        panel.orderOut(nil)
    }

    private func follow() {
        let pointer = NSEvent.mouseLocation
        panel.setFrameOrigin(CGPoint(x: pointer.x - grab.x - 16, y: pointer.y - grab.y - 16))
    }
}
