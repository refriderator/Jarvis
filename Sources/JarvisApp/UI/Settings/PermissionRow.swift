import AppKit
import JarvisKit
import SwiftUI

/// One permission with its state and the button that fits it.
struct PermissionRow: View {
    let state: AppState
    let permission: Permission
    @State private var status: PermissionStatus = .notAsked

    var body: some View {
        LabeledContent {
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notAsked:
                Button("Allow") {
                    Task { status = await state.permissions.request(permission) }
                }
            case .denied:
                Button("Open System Settings") {
                    if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                }
            }
        } label: {
            Text(permission.title)
            Text(permission.reason)
        }
        .onAppear { status = state.permissions.status(permission) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = state.permissions.status(permission)
        }
    }
}
