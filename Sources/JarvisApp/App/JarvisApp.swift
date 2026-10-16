import JarvisKit
import SwiftUI

struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: delegate.state.binding(\.showInMenuBar)) {
            JarvisMenu(state: delegate.state, voice: delegate.voice, timers: delegate.timers,
                       openSettings: delegate.showSettings)
        } label: {
            Image(nsImage: MenuBarIcon.image(quickDock: delegate.state.settings.quickDock))
        }
    }
}
