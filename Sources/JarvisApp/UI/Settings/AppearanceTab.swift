import JarvisKit
import SwiftUI

struct AppearanceTab: View {
    let state: AppState

    var body: some View {
        Form {
            Picker("Skin", selection: state.binding(\.skinID)) {
                ForEach(SkinCatalog.all) { skin in
                    Text(skin.name).tag(skin.id)
                }
            }
            .pickerStyle(.radioGroup)
            Picker("Caption size", selection: state.binding(\.captionSize)) {
                Text("Small").tag(CaptionSize.small)
                Text("Regular").tag(CaptionSize.regular)
                Text("Large").tag(CaptionSize.large)
            }
            .pickerStyle(.segmented)
        }
    }
}
