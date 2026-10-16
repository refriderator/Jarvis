import SwiftUI

extension View {
    /// Liquid Glass tinted with `tint` (macOS 26); before that, the frosted material it replaced, tinted the same.
    @ViewBuilder func glass<S: Shape>(tint: Color, in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(tint, in: shape).background(.ultraThinMaterial, in: shape)
        }
    }
}
