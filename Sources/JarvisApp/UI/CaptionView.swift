import JarvisKit
import SwiftUI

/// The caption: the question and its answer.
/// Click it to keep it on screen in full until you click off.
struct CaptionView: View {
    let turn: Turn
    let skin: Skin
    let size: CaptionSize
    let speaking: Bool
    let pinned: Bool
    let showsSummary: Bool
    let togglePin: () -> Void
    /// Asks for the summary, or switches between it and the answer once there is one.
    let summarize: () -> Void
    let useCloud: () -> Void
    let skipCloud: () -> Void
    let stopSpeaking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !turn.question.isEmpty {
                Text(turn.question)
                    .font(.caption)
                    .opacity(0.55)
                    .lineLimit(1)
            }
            ScrollView {
                Group {
                    if turn.awaitingCloud {
                        askBeforeCloud
                    } else if showsSummary, let summary = turn.summary {
                        SummaryView(summary: summary, skin: skin, font: font)
                    } else if let answer = turn.answer {
                        Text(answer)
                            .foregroundStyle(turn.failed ? Color.orange : skin.foreground)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").opacity(0.6)
                        }
                    }
                }
                .font(font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if pinned {
                    Label("kept · click outside to close", systemImage: "pin.fill")
                        .font(.caption2)
                        .opacity(0.45)
                }
                // Who answered: Jarvis (code or its local model), Siri (Apple's apps), Apple Intelligence or Claude.
                if let answerer = Answerer.of(turn) {
                    Label(answerer.text, systemImage: answerer.icon)
                        .font(.caption2)
                        .opacity(0.5)
                        .lineLimit(1)
                }
                Spacer()
                if turn.cloud, turn.answer != nil, !turn.failed {
                    summaryButton
                }
                if speaking {
                    // The stop key is only taken while Jarvis talks.
                    Button(action: stopSpeaking) {
                        Text("\(Hotkey.stop.text) stop")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(skin.foreground.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePin)
    }

    /// Summarize, then a switch back to the full answer (and to the summary again).
    private var summaryButton: some View {
        Button(action: summarize) {
            HStack(spacing: 4) {
                if turn.summarizing {
                    ProgressView().controlSize(.mini)
                    Text("Summarizing…")
                } else if turn.summary == nil {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Summarize")
                } else {
                    Text(showsSummary ? "Full answer" : "Summary")
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(skin.foreground.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(turn.summarizing)
    }

    /// Token saving: the question needs the cloud brain, so ask first.
    private var askBeforeCloud: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This needs \(turn.source ?? "the cloud brain"). Use it?")
            HStack {
                Button("Use it", action: useCloud)
                Button("Skip", action: skipCloud)
            }
            .controlSize(.small)
        }
    }

    private var font: Font {
        switch size {
        case .small: .callout
        case .regular: .body
        case .large: .title3
        }
    }
}
