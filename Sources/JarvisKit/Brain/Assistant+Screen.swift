import Foundation

/// Text on screen (`TextJob`): Apple Intelligence summarizes the page or the selection, or rewrites the selection.
/// Without Apple's model (macOS before 26, or Apple Intelligence off), the cloud brain does it with the same text.
extension Assistant {
    nonisolated static let onDeviceSource = "Apple Intelligence"
    /// The most page text handed to a cloud brain when Apple's model can't take it.
    static let cloudPageChars = 40_000

    /// True when the question was a text job (answered or failed); false lets the brains answer it.
    func answeredOnScreen(_ text: String) async -> Bool {
        guard let job = TextJob.parse(text), let screen = tools.screen else { return false }
        let selected = screen.selection()
        switch job {
        case .rewrite(let instruction):
            // Nothing selected: "rewrite this" is about something else, so a brain takes it.
            guard let selected else { return false }
            await rewrite(selected, instruction: instruction, screen: screen)
        case .summarize(let target):
            if target == .selection || (target == .either && selected != nil) {
                guard let selected else {
                    fail("Select some text first, then ask me to summarize the selection.")
                    return true
                }
                await summarize(selected, title: "")
            } else {
                do {
                    let page = try screen.page()
                    await summarize(page.text, title: page.title)
                } catch {
                    fail(error.localizedDescription)
                }
            }
        }
        return true
    }

    private func summarize(_ text: String, title: String) async {
        guard let model = makeOnDevice() else {
            let prompt = (title.isEmpty ? "" : "Title: \(title)\n\n") + String(text.prefix(Self.cloudPageChars))
            await toCloud([ChatMessage(.user, TextJob.summarySystem + "\n\n" + prompt)],
                          note: " · Apple Intelligence off", needs: .init())
            return
        }
        do {
            let summary = try await TextJob.summarize(text, title: title, with: model)
            let answer = Readable.clean(summary.text) + (summary.cut ? " (That's the first part; the page is long.)" : "")
            finish(answer, source: Self.onDeviceSource, tokens: 0)
        } catch {
            fail("Apple Intelligence couldn't summarize it: \(error.localizedDescription)")
        }
    }

    private func rewrite(_ text: String, instruction: String, screen: ScreenTextSource) async {
        guard let model = makeOnDevice() else {
            await toCloud([ChatMessage(.user, TextJob.rewriteSystem + "\n\nRequest: \(instruction)\n\nText:\n\(text)")],
                          note: " · Apple Intelligence off", needs: .init())
            return
        }
        do {
            let rewritten = try await TextJob.rewrite(text, instruction: instruction, with: model)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            screen.copy(rewritten)
            finish("Copied, paste it with ⌘V:\n\n" + rewritten, source: Self.onDeviceSource, tokens: 0)
        } catch {
            fail("Apple Intelligence couldn't rewrite it: \(error.localizedDescription)")
        }
    }
}
