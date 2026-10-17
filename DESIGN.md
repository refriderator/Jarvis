# Jarvis — design

A Mac assistant that lives in the notch. Talk or type; it answers with captions and voice, and can use your calendar,
Notion, timers and windows. Clean, small, easy to fix.

This file holds what the code can't say: why things are the way they are, what was tried and dropped, and limits that
come from macOS. Sizes, timings and animation steps live in the code (`NotchLayout`, `NotchMotion`, …), not here.

Status: M1–M5 done (notch, settings, welcome, chat, voice, tools), plus the window dock, video, Finder, Monitor and Web tabs.

## Decisions
| Topic | Decision |
|---|---|
| Language | Swift, SwiftUI + AppKit for the notch. A Swift package, no Xcode project (see Build). |
| macOS | 15.6 and newer, one build. 15.6 is the oldest that Apple's Swift 6.2 tools install on. What needs 26 (Apple's on-device model, Liquid Glass) is checked at runtime with `#available`. |
| Speech to text | Apple's speech recognition, on device when the language allows. No bundled model. |
| Voice | Installed Apple voices (incl. Premium/Enhanced and Personal Voice), behind a `Speaker` protocol. |
| Brain | Local first, cloud for the rest (see Brain). Keys in Keychain only. |
| Calendar | EventKit, so any calendar added to macOS (Google, iCloud, Exchange) counts. A direct Google sign-in would need a registered Google Cloud OAuth app. |
| Notion | User-pasted integration token, in Keychain. |
| Money | Never shown anywhere. Tokens are still counted (`TokenMeter`) but no longer shown (10-17). |
| Distribution | GitHub, MIT, built from source. Notarized releases would need Xcode and a paid developer account. |

## Notch
- States **idle → peek → open**. Open on hover, or on click with hover only peeking (Settings › General).
- Closes when the pointer leaves, a click lands outside, or Esc. While a caption is up, the pointer leaving doesn't close it.
- Sits on the Mac's own display unless another is picked (kept by vendor, model and serial, so it comes back to the
  right monitor). Displays without a notch get a pill showing the **ticker** (time, music, battery, weather, next
  event, one line at a time; Settings › Display).
- **Captions:** the answer replaces the Today list under the time, stays a reading pause, then closes. A reply never
  opens a new dropdown, except when you closed it mid-answer: then it pops back once. Click a caption to keep it.
  Cloud answers have **Summarize** (`Summary`: a few points, a formula, a small chart, as JSON from the cloud brain).
- **Tabs** (left of the notch): Today, Finder, Monitor, Web. Clicking the showing tab folds it away.
  - **Finder** (`FolderShelfView`): Jarvis's own folder view, starting at Downloads. Drag in and out like Finder
    (`FileDragSource`: SwiftUI's own drag only ever offered a copy, never a move). Its sidebar pins are Jarvis's own
    (`finderPins`) because Finder's sidebar list is private to Finder. Search uses Spotlight.
  - **Monitor**: CPU, memory, network, compressed memory and swap, from the same counters Activity Monitor reads,
    only while the tab is showing. Network is numbers, not a graph: a graph scaled to the peak made blips look huge.
  - **Web** (`BrowserController`): a small WebKit browser. The user agent says Safari, or sites call it out of date.
    Full screen is Jarvis's own (`PageFullscreen`): the system's took over the whole screen, and reshaping the
    dropdown around the video broke YouTube's full-window mode. Passwords (`PasswordHelper`) run in their own
    content world so page scripts can't see them, fill only on https for the exact host, and save to the login Keychain.
- **Keep** holds the dropdown open (and with a video held, makes the video Large).
- **Mission Control** (`MissionControlWatch`): Jarvis fades out while it's open. macOS doesn't announce it, so Jarvis
  checks the Dock's accessibility tree for the group with identifier "mc" (a full-screen Dock window also shows
  when the Dock is merely shown, so that test was dropped).

## Holding windows
`JarvisKit/Dock/`, `DockController`; needs Accessibility. Settings › General "Hold windows in the notch".
- Drag a window by its title bar (the top 56 pt only, so dragging a file out of a window never counts) onto the notch
  or a display's left/right edge. Catching uses hysteresis (`DockCatch`) so nothing flickers on an edge.
- A Finder window dropped on the notch closes and opens its folder in the Finder tab (folder read via AppleScript;
  Accessibility doesn't say).
- Other windows slide off the nearer edge with 1 pt showing (`SideDock`), still real windows on their own desktop.
  Pointing at the edge shows cards for them (`SidePeek`); click one to use it, it slides back when the pointer
  leaves. Sides with another display against them aren't used; with no free side the window is minimized into the
  notch's strip instead. Up to 6 per desktop.
- Each desktop has its own strip. Other displays get a small tray from the menu bar (`ScreenTrays`).
- Letting go puts a window back where it was; quitting Jarvis puts every held window back.
- Why cards and not real shrunk windows: macOS has no public way to scale another app's window, and raising one
  without activating its app doesn't put it above the app in front. The first version held the real window under a
  hole in the notch; macOS owns real windows' desktops, stacking and Mission Control, so it glitched on all three.
- Desktops are read (never changed) through SkyLight's private calls (`Desktops`); there is no public API.
- **Quick Dock** (`QuickDock`): one window per desktop. The app you bring forward fills the desktop and the rest go to
  the sides. Refuses to turn on past 7 windows on a desktop; changing desktops in Mission Control turns it off.

## Video
`VideoController`, `VideoDock`. A browser's Picture in Picture window can be held by the notch: open, beside the time;
closed, as a mini player in the notch; or tucked into a side tab.
- The video is the browser's real window floating below Jarvis's panel, showing through a hole in the notch. The
  hole is cut to the frame the browser actually gave it (browsers keep their own aspect ratio, and macOS can nudge a
  window near the menu bar), so it's read back after placing. A browser that won't shrink that far is remembered.
- Every change plays behind a **clamshell** cover: it closes, the notch reshapes, the video moves, it opens. That way
  the video never shows outside the notch. Tucking morphs one shape (`TuckMorph`) rather than swapping views.
- Tucked, the video has its own tab (`TuckedVideoTab`, `videoTabFrame`) and held apps keep theirs, notch-high, in
  front of it along the top, where the tab is beside the notch and the video (below it) isn't. One shared tab put
  the icons on top of the video icon. The video's tab cuts the apps' tab's shape out of itself, so Liquid Glass
  doesn't show a darker band where two glass layers overlap.
- PiP windows are found by floating window, then title through Accessibility: the WindowServer's titles need
  Screen Recording.
- Holding a video, the panel never takes the keyboard on its own: giving it back meant hiding the panel for a frame,
  a visible flash.
- The notch reacts only to its mode really changing; reacting to other fields of `notch` made the cover close every
  time it opened.

## Voice and keys
- Global shortcuts (Carbon hotkey API, no permission needed): talk ⌥Space, type ⌥⇧Space, recordable in General.
  Talk is hold or toggle.
- Listening ends after a pause (`EndOfSpeech`), judged from the transcript, not the audio, so room noise doesn't keep
  it open. Not while holding the talk key.
- Only spoken questions (and timers) are read aloud; typed ones are captioned only.
- The stop key is registered only while Jarvis is speaking, so it never steals a key like Esc otherwise.

## Menu
Talk, Type, Quick Dock, Skin, Open the Notch On, Notch On, Timers, Settings, Quit. Jarvis must work fully with the menu
icon hidden: it runs as an accessory app, and Settings is reachable from the notch, a hotkey, or relaunching.

## Settings
Tabs: General, Voice, Appearance, Display, Connections, Features (a searchable guide, one entry per feature).
Settings are one `Settings` struct saved to a file; the window is a form over it. New toggle = one field + one row.
- **Update** (General, `Updater`): opens Terminal to `git pull` and run the installer in the folder this copy was built
  from (`bundle.sh` writes it into Info.plist as `JarvisSourceFolder`). Terminal, not the background, because the
  installer quits Jarvis, and so errors and Apple's license prompt can be seen and answered.
- **Welcome:** first run. Meet (and name it; `AssistantName` warns about names like "Claude" or command words), set
  up (permissions, look, voice, brains), tips.
- **Brain setup** (Connections): `MacAdvice` reads chip, memory and disk and suggests brains. Claude Code and Codex
  can be installed and signed in from Jarvis (`ClaudeCodeSetup`, `CodexSetup`); sign-in needs a browser, so it opens
  one Terminal window.

## Skins
A skin is a small struct (colours, radius, glow, font, shoulders, material) in its own file; add a file and register it
in `SkinCatalog`. Shipped: Classic (default), Liquid Glass, Midnight, Arc, Pink, Terminal.

## Brain
Most questions never reach the cloud:
1. **Plain code** for fixed commands: timers and reminders (`TimerCommand`), "add X to my calendar tomorrow at 3pm",
   "good morning" (`MorningBrief`), local weather, "dock Safari". Instant and free.
2. **Local brain** (Apple on-device, built-in llama.cpp Qwen3, or Ollama) tries everything else, except anything
   recent (news, scores), the camera and Notion. A local model with tools is a *function bot*: it only acts through
   its tools (`LocalToolLoop`, one line of JSON per call) and answers `ESCALATE` for facts, explanations and writing.
   Every value is checked by the tool (timer 1 s–24 h, real calendar ids), so a wrong guess is refused, not acted on.
   Notion always goes to the cloud: the 8B model misread which item was next too often (10-17).
3. **Cloud brain**: Claude Code (`claude -p`, the user's subscription, default), Codex (`codex exec`, the user's
   ChatGPT plan), the Claude API, or any OpenAI-compatible endpoint. Claude Code runs stripped down (no MCP, skills or
   settings, empty folder): about 1k tokens a question instead of about 138k.
- **Claude's access** (Connections: None / Tools / Full). Tools gives the cloud brain Jarvis's own tools; Claude Code
  reaches them through `Jarvis --tools-mcp`, relayed over a user-only socket to the running app (`ToolRelay`). Full
  adds file and shell tools on the home folder, allowed up front because `claude -p` can't ask.
- Every question starts with the time and the next 7 days' dates (`Persona.context`), so small models look dates up
  instead of working them out.
- Answers are one short plain paragraph (`Persona`), since they're captioned and spoken. `Readable` turns any stray
  LaTeX or markdown into plain text (x², √2).
- Ollama is asked to skip thinking: Qwen3 otherwise thinks for most of a minute and can return nothing.
- "Ask before cloud" (off by default) asks "Use it?" first; "Claude, …" skips it. Follow-ups send the last 3 turns
  from the last 5 minutes.
- Conversation log (`TurnLog`, off by default): every model call raw, one JSONL file a day, for training on real use.
  The fine-tuned "Jarvis 8B" is trained outside this repo and only listed once its GGUF is in the Models folder.
- Open question: Anthropic's terms limit third-party apps using people's subscriptions; check before publishing with
  Claude Code as the default.

## Tools
`JarvisKit/Tools/`. `Toolbox` decides what a request needs.
- **Timers and reminders**, no alarms: Jarvis can't wake a sleeping Mac or reach a phone, so an alarm request is
  answered with what to say instead.
- **Calendar**: list, add, change and delete single events by real ids; a delete must also name the event.
- **Notion**: due items, search, read, append, tick, create. For Claude Code, Jarvis runs itself as the only MCP
  server (`Jarvis --notion-mcp`); the token goes through the environment, never the command line, a file or logs.
- **Camera**: one photo, after any ask-before-cloud check. OpenAI-compatible brains can't use Notion or the camera.
- **Mac tools**: open apps, dock and undock windows, Quick Dock. **Maths**: a calculator, so models don't do arithmetic.

## Code layout
```
Sources/JarvisKit/      the logic, testable from the command line
  Core/     AppState, Settings, Keychain, TokenMeter, AssistantName
  Brain/    providers (Claude Code, Codex, Claude API, OpenAI-compatible, Apple, llama.cpp), Router, Assistant, Persona
  Browser/  Web tab tabs, bookmarks, passwords
  Dock/     held windows, side dock, video, Finder shelf, desktops
  Notch/    layout, state machine, ticker
  Setup/    Mac advice, Claude Code and Codex setup, Updater
  Tools/    timers, calendar, Notion, camera, maths, Mac tools, MCP server
  Voice/    listener, speaker, hotkeys
  Skins/    Skin struct + one file per skin
  Widgets/  now playing, weather, battery, system stats, Today list
Sources/JarvisApp/      thin app target: windows, notch views, settings UI
Tests/JarvisKitTests/
```
Rules: files under ~300 lines, one job each. One `AppState`; views only read it. Services behind protocols. No globals.

## Not yet
An iPhone link, other personas, a direct Google Calendar connection.

## Build
No Xcode project: `scripts/bundle.sh` wraps the `Jarvis` executable into `build/Jarvis.app`, so Command Line Tools are
enough. `scripts/install.sh` (run by `Install Jarvis.command`) checks the Mac, makes the signing cert, bundles a release
and installs it. `scripts/test.sh` adds the Swift Testing paths the Command Line Tools need.

Signing: ad-hoc signatures change every build, so macOS re-asks for permissions and Keychain access each time.
`scripts/make-signing-cert.sh` makes a self-signed "Jarvis Local Signing" cert once, keeping the app's identity stable.
