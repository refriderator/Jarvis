import JarvisKit
import SwiftUI

/// Starts the app, or with `--notion-mcp` runs as the Notion MCP server Claude Code talks to, or with `--tools-mcp`
/// as the MCP server that passes Claude Code's calls on to the running app's Mac tools (`ToolRelay`).
/// `--local-prompt "question"` prints the local model's system prompt and exits.
@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains(NotionTools.flag) {
            // Jarvis passes the token in through Claude Code; the Keychain is only a fallback for running it by hand.
            let passed = ProcessInfo.processInfo.environment[NotionTools.tokenVariable]
            guard let token = passed.flatMap({ $0.isEmpty ? nil : $0 }) ?? KeychainStore().get(.notionToken) else {
                FileHandle.standardError.write(Data("No Notion token saved in Jarvis.\n".utf8))
                exit(1)
            }
            Task {
                await MCPServer.run(NotionTools(token: token))
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains(ToolRelay.flag) {
            do {
                let kit = try ToolRelay.Client()
                Task {
                    await MCPServer.run(kit)
                    exit(0)
                }
                dispatchMain()
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--local-prompt"), flag + 1 < CommandLine.arguments.count {
            // For fine-tuning scripts: print the exact system prompt a local model gets for this question (Notion tools).
            print(MainActor.assumeIsolated { localPrompt(for: CommandLine.arguments[flag + 1]) })
            return
        }
        JarvisApp.main()
    }
}

/// A calendar that is never read; only its tool definitions matter for the prompt.
private struct NoCalendar: CalendarSource {
    func events(from start: Date, to end: Date) -> [AgendaItem]? { nil }
    func add(title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        AgendaItem(id: "", title: title, start: start, end: end, allDay: allDay)
    }
    func event(id: String) -> AgendaItem? { nil }
    func change(id: String, title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        AgendaItem(id: id, title: title, start: start, end: end, allDay: allDay)
    }
    func delete(id: String) throws {}
}

/// The local tool-loop system prompt for a question, built by the same code the app uses to pick tools
/// (timers, calendar, Mac tools; Notion goes to the cloud brain); nothing is ever called.
@MainActor
private func localPrompt(for question: String) -> String {
    let kit = NotionTools(token: "x")
    let toolbox = Toolbox(timers: TimerCenter(state: AppState()), calendar: NoCalendar(), mac: MacControls(), notion: { kit })
    let needs = toolbox.needs(question)
    let kits = toolbox.localKits(for: question, needs: needs)
    return LocalToolLoop.systemPrompt(kits: kits, hint: toolbox.localHint(for: question, kits: kits, needs: needs))
}
