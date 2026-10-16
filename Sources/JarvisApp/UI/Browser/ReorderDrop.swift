import SwiftUI
import UniformTypeIdentifiers

/// Live drag-to-reorder for the Web tab's tabs and bookmarks: as the dragged item passes over another, it takes
/// that one's place and the rest slide over to make room, so it's dropped into the gap it's shown in.
struct ReorderDrop<ID: Equatable>: DropDelegate {
    let target: ID
    @Binding var dragging: ID?
    let move: (ID, ID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Ends a reorder dropped anywhere else in the strip or grid (between items, past the end).
struct ReorderEnd<ID: Equatable>: DropDelegate {
    @Binding var dragging: ID?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    /// Makes this item draggable within its list, reordering live (see `ReorderDrop`). The item being dragged
    /// fades while it's moved.
    func reorderable<ID: Equatable>(_ id: ID, dragging: Binding<ID?>, move: @escaping (ID, ID) -> Void) -> some View {
        opacity(dragging.wrappedValue == id ? 0.35 : 1)
            .onDrag {
                dragging.wrappedValue = id
                return NSItemProvider(object: "jarvis-reorder" as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDrop(target: id, dragging: dragging, move: move))
    }

    func endsReorder<ID: Equatable>(dragging: Binding<ID?>) -> some View {
        onDrop(of: [.text], delegate: ReorderEnd(dragging: dragging))
    }
}
