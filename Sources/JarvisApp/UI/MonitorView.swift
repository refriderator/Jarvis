import JarvisKit
import SwiftUI

/// The Monitor tab: CPU and memory with their graphs over the last minute, then network speeds and how much
/// memory macOS has offloaded (compressed, and swapped to disk), as numbers.
struct MonitorView: View {
    let history: StatsHistory
    let skin: Skin

    var body: some View {
        let tint = skin.foreground
        HStack(alignment: .top, spacing: 14) {
            GraphRow(title: "CPU", value: percent(history.latest?.cpu), detail: cores,
                     points: [history.cpu], colors: [skin.accent], tint: tint)
            GraphRow(title: "Memory", value: percent(history.latest?.memory), detail: memory,
                     points: [history.memory], colors: [tint.opacity(0.8)], tint: tint)
            // Numbers only: a graph scaled to the minute's peak made a 7 KB/s blip look like a flood.
            VStack(alignment: .leading, spacing: 3) {
                Text("Network").font(.caption.weight(.semibold)).foregroundStyle(tint.opacity(0.6))
                Text(history.latest.map { "↓ " + rate($0.netIn) } ?? "–").font(.callout.weight(.semibold).monospacedDigit())
                Text(history.latest.map { "↑ " + rate($0.netOut) } ?? "").font(.callout.weight(.semibold).monospacedDigit())
                Spacer(minLength: 4)
                Text("Memory Offload").font(.caption.weight(.semibold)).foregroundStyle(tint.opacity(0.6))
                Text(offload).font(.caption.monospacedDigit()).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if history.latest == nil {
                Text("Measuring…").font(.caption).foregroundStyle(tint.opacity(0.5))
            }
        }
    }

    private var cores: String {
        "\(ProcessInfo.processInfo.activeProcessorCount) cores"
    }

    private var memory: String {
        guard let latest = history.latest else { return "" }
        let gb = { (bytes: UInt64) in String(format: "%.1f", Double(bytes) / 1_073_741_824) }
        return "\(gb(latest.memoryUsed)) of \(gb(latest.memoryTotal)) GB"
    }

    /// What macOS has moved out of RAM to make room: squeezed in place, and written to disk.
    private var offload: String {
        guard let latest = history.latest else { return "–" }
        return "\(gigabytes(latest.compressed)) compressed\n\(gigabytes(latest.swapUsed)) swap"
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? "–"
    }

    private func rate(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + "/s"
    }
}

private struct GraphRow: View {
    let title: String
    let value: String
    let detail: String
    let points: [[Double]]
    let colors: [Color]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint.opacity(0.6))
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).lineLimit(1)
            Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(tint.opacity(0.55)).lineLimit(1)
            ZStack {
                ForEach(points.indices, id: \.self) { i in
                    Sparkline(points: points[i], color: colors[i], filled: i == 0)
                }
            }
            .background(colors[0].opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A filled line over the last minute: 0 at the bottom, 1 at the top, newest on the right.
private struct Sparkline: View {
    let points: [Double]
    let color: Color
    var filled = true

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let step = size.width / CGFloat(StatsHistory.length - 1)
            let start = size.width - step * CGFloat(points.count - 1)
            var line = Path()
            for (i, value) in points.enumerated() {
                let point = CGPoint(x: start + step * CGFloat(i), y: size.height * (1 - min(max(value, 0), 1)))
                i == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: start, y: size.height))
            fill.closeSubpath()
            if filled { context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))) }
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        }
    }
}
