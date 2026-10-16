import JarvisKit
import SwiftUI

extension AppState {
    /// A binding to one settings field; writes go through `update` so they are saved.
    func binding<Value>(_ field: WritableKeyPath<JarvisKit.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: field] },
                set: { value in self.update { $0[keyPath: field] = value } })
    }
}
