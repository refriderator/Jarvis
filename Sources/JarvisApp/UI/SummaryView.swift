import AppKit
import Charts
import JarvisKit
import SwiftUI

/// An answer's summary in the caption: the key formula on its own line, a point per row with an icon,
/// then a small bar chart when the answer compared numbers.
struct SummaryView: View {
    let summary: Summary
    let skin: Skin
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let formula = summary.formula {
                Text(formula)
                    .font(.title3.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(skin.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol(point.symbol))
                        .foregroundStyle(skin.accent)
                        .frame(width: 18)
                    Text(point.text)
                }
                .font(font)
            }
            if !summary.bars.isEmpty {
                chart
            }
        }
    }

    private var chart: some View {
        Chart(Array(summary.bars.enumerated()), id: \.offset) { _, bar in
            BarMark(x: .value("Value", bar.value), y: .value("Label", bar.label))
                .foregroundStyle(skin.accent.gradient)
                .annotation(position: .trailing) {
                    Text(bar.value.formatted()).font(.caption2).opacity(0.6)
                }
        }
        .chartXAxis(.hidden)
        .chartXAxisLabel(summary.unit ?? "", alignment: .trailing)
        .frame(height: 90)
    }

    /// The model's symbol if macOS has it, else a dot.
    private func symbol(_ name: String?) -> String {
        guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return "circle.fill" }
        return name
    }
}
