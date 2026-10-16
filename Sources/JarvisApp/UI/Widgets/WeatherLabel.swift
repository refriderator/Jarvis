import JarvisKit
import SwiftUI

/// "it's warm" over "24° · feels 25°", right-aligned beside the time.
struct WeatherLabel: View {
    let weather: WeatherReport?
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let weather {
                HStack(spacing: 6) {
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                    Text(weather.headline)
                }
                .font(.system(size: 20, weight: .bold))
                Text(weather.detailText + (weather.place.map { " · \($0)" } ?? ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.5))
            } else {
                Text("no weather yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.4))
            }
        }
        .lineLimit(1)
    }
}
