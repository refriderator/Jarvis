# Jarvis

Read DESIGN.md first; it is the source of truth for decisions, layout and milestones.

## Rules
- Swift, SwiftUI + AppKit. Logic in the `JarvisKit` package, thin app target on top.
- Files under ~300 lines, one job each. One `AppState`. Services behind protocols. No globals.
- Tokens only, never money, in any UI.
- Secrets in Keychain only, never in settings files or logs.
- Match the existing code's naming and comment density. Keep it readable over clever.
- Build milestone by milestone (M1..M5); don't jump ahead.
