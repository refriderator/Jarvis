import AppKit
import SwiftUI

/// Makes a file in the Finder tab draggable the way Finder's own are. SwiftUI's `onDrag` only offers other apps
/// a copy, so a file dragged into a Finder window was copied and stayed here; this offers a move too, and
/// Finder picks (move on the same disk, copy across disks or with Option), exactly as with its own files.
/// It also reports where the pointer is while dragging, so the notch can let go of drops that aren't on it.
/// Double-click opens; right-click shows `menu`.
struct FileDragSource: NSViewRepresentable {
    let url: URL
    let open: () -> Void
    let menu: () -> [(String, () -> Void)]
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.source = self
    }

    final class DragView: NSView, NSDraggingSource {
        var source: FileDragSource?
        private var downAt: NSPoint?
        /// Kept alive while the menu is up, so its items can call back.
        private var menuActions: [() -> Void] = []

        override func mouseDown(with event: NSEvent) {
            downAt = event.locationInWindow
            if event.clickCount == 2 { source?.open() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let source, let downAt else { return }
            let p = event.locationInWindow
            guard hypot(p.x - downAt.x, p.y - downAt.y) > 3 else { return }
            self.downAt = nil
            let item = NSDraggingItem(pasteboardWriter: source.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: source.url.path)
            let side: CGFloat = 32
            item.setDraggingFrame(NSRect(x: bounds.midX - side / 2, y: bounds.maxY - side - 2, width: side, height: side),
                                  contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            downAt = nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let source else { return nil }
            let menu = NSMenu()
            menuActions = []
            for (index, (title, action)) in source.menu().enumerated() {
                menuActions.append(action)
                let item = NSMenuItem(title: title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            return menu
        }

        @objc private func runMenuItem(_ item: NSMenuItem) {
            guard menuActions.indices.contains(item.tag) else { return }
            menuActions[item.tag]()
        }

        // MARK: NSDraggingSource

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Inside Jarvis (the sidebar) nothing moves; elsewhere the destination picks, as with Finder's files.
            context == .withinApplication ? .link : [.move, .copy, .generic]
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            source?.moved(screenPoint)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            source?.ended()
        }
    }
}
