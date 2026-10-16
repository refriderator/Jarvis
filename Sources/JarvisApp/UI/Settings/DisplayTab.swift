import JarvisKit
import SwiftUI

/// Settings › Display: which display the notch is on, and what its bar shows there when that display has no
/// hardware notch.
struct DisplayTab: View {
    let state: AppState

    var body: some View {
        Form {
            Section {
                DisplayPicker(state: state, title: "Show the notch on")
            } footer: {
                note("Unplug that display and the notch goes back to this Mac's own until it's plugged in again.")
            }
            Section {
                ForEach(TickerItem.allCases) { item in
                    Toggle(item.title, isOn: shows(item))
                }
                LabeledContent("Each one shows for") {
                    Stepper("\(Int(state.settings.tickerSeconds)) seconds", value: state.binding(\.tickerSeconds),
                            in: 2...30, step: 1)
                }
            } header: {
                Text("Notch on a display without one")
            } footer: {
                note("The bar at the top of a display without a notch shows these one at a time, fading from one "
                     + "to the next. Ones with nothing to show (no song playing, no battery) are skipped. Turn them "
                     + "all off for a plain black bar.")
            }
        }
    }

    /// On or off for one item, keeping them in the order they're listed here.
    private func shows(_ item: TickerItem) -> Binding<Bool> {
        Binding(get: { state.settings.tickerItems.contains(item) }, set: { on in
            state.update { settings in
                let picked = Set(settings.tickerItems).symmetricDifference(settings.tickerItems.contains(item) == on ? [] : [item])
                settings.tickerItems = TickerItem.allCases.filter(picked.contains)
            }
        })
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
