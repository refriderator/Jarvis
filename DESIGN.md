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
  right monitor). Moving it rises off one display and drops onto the other with a bounce (`NotchHop`), and every
  tray does the same. Only where there's no hardware notch: beside one, the closed notch is drawn as that notch and
  tabs hang from it, so rising or stretching looked like the notch (or a tab's base) moving; there the tabs slide in
  behind the notch and spring back out. Moved down, the screen's edge showed above it, so the dip and bounce stretch
  from the top edge instead. An open dropdown closes first. With a video held it moves at once and the video goes
  with it (a real window can't rise with the notch); a full-screen video is never held or offered, so it stays. Displays without a notch get a pill showing the **ticker** (time, music, battery, weather, next
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
- Each desktop has its own strip. Other displays get a small tray from the menu bar (`ScreenTrays`); the Mac's own
  display, while the notch is on another, gets a tab with the dot on the hardware notch's right (like the apps' tab
  beside the notch, starting under the notch's flat bottom, clear of its round corner) that opens to the same grid
  hanging below the notch, wider than it so no corner hides behind the notch's round ones. Between the two, one
  goes in before the other comes out (the grid folds up behind the notch, then the tab springs out; and back):
  morphed in one go, the shapes slid across each other. A tray's window covers
  every stage and takes clicks only over the tray. A window dragged over a tray shows its app's icon in the next
  empty place.
- Letting go puts a window back where it was; quitting Jarvis puts every held window back.
- Picking a held window in Mission Control pops it out like its card does, and the first move of the pointer away
  (not onto it) sends it back: it was never under the pointer, so otherwise it stayed out. ⌘-Tab still waits for the
  pointer to have been on it, since you'd move toward it to use it.
- The cards show live pictures of the windows (Settings › General "Window previews", on by default; needs Screen
  Recording, asked for only from that row), else the app's icon and title.
- A window put in the notch (or a tray) is held on that display, wherever it was dragged from: parked on that
  display's side, so it shows in that display's strip. Held on its own display, it showed on the side but not in
  the notch it was put in. Letting go still puts it back where it really was.
- Moving the notch to another display moves no held window: each stays on the display it was put on and shows in
  that display's strip (the notch's, or its tray). The notch's strip follows the desktop showing on its own display,
  read again on every layout (`DockController.notchMoved`); left on the old one, it listed the other display's.
- A window taken out of a side (popped out, dragged by its title bar) never opens the notch's drop box or a tray:
  its drops are the middle of the display (let go of) or another edge (moved there).
- Why cards and not real shrunk windows: macOS has no public way to scale another app's window, and raising one
  without activating its app doesn't put it above the app in front. The first version held the real window under a
  hole in the notch; macOS owns real windows' desktops, stacking and Mission Control, so it glitched on all three.
- Desktops are read (never changed) through SkyLight's private calls (`Desktops`); there is no public API.
- Jarvis's own windows never slide: each goes straight where it ends and its content animates inside it. A window
  moved frame by frame makes AppKit set the cursor again each frame, and a customized pointer (Accessibility's size
  or colour) is redrawn on the CPU each time (`_AXFMouseCursorGenerator`), on the main thread: the side cards
  stuttered. Found by sampling the app while they stuttered.
- Accessibility calls wait for the other app on the main thread, so they're kept rare and short: held windows are
  checked twice a second (not while cards are out), and every call gives up after 0.5 s (`AXWindowControl.timeout`).
  Checked 30 times a second with the 6 s default, a busy app made the side cards stutter.
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
- **Uninstall** (General, `Uninstaller`): `scripts/uninstall.sh`, copied into the app by `bundle.sh` so it works
  without the source folder, and run from a temp copy since it deletes the app. It lists what goes with sizes and
  needs `yes` typed (models can be many GB). Apps are matched by bundle id, not name. It leaves website passwords
  from the Web tab (the user's login keychain) and Claude Code, Codex and Ollama (separate tools).
- **Large switches lock the dropdown** (`VideoDock.switching`) until they finish: leaving Large drops the Keep lock
  at once while the hover area is still Large's small frame, so a pointer outside it closed to the mini player.
- **Welcome:** first run. Meet (and name it; `AssistantName` warns about names like "Claude" or command words), set
  up (permissions, look, voice, brains), tips.
- **Brain setup** (Connections): `MacAdvice` reads chip, memory and disk and suggests brains. Claude Code and Codex
  can be installed and signed in from Jarvis (`ClaudeCodeSetup`, `CodexSetup`); sign-in needs a browser, so it opens
  one Terminal window.

## Skins
A skin is a small struct (colours, radius, glow, font, shoulders, material) in its own file; add a file and register it
in `SkinCatalog`. Shipped: Classic (default), Liquid Glass, Midnight, Arc, Pink, Terminal.

## Brain
Most questions never reach the cloud. Each tier does what it's good at, and code (never a model) decides, since a
deciding model would add a call to every question:
1. **Plain code** for fixed commands: timers (`TimerCommand`), reminders and alarms (`ReminderCommand`,
   `AlarmCommand`), "run my X shortcut", "add X to my calendar tomorrow at 3pm", "good morning" (`MorningBrief`),
   local weather, "dock Safari". Instant and free.
2. **Apple Intelligence** for text already on screen (`TextJob`): summarizing the page in Safari or Chrome or the
   selection, rewriting the selection (copied, not pasted over). Free, private, and what Apple's ~3B model is good
   at; it reads only about 4k tokens, so long pages are summarized in parts, then together. Without it (before macOS
   26, or switched off) the cloud brain gets the same text. Kept off the local Qwen so its training is only tools
   and knowing when to escalate.
3. **Local brain** (Apple on-device, built-in llama.cpp Qwen3, or Ollama) tries everything else, except anything
   recent (news, scores), the camera and Notion. A local model with tools is a *function bot*: it only acts through
   its tools (`LocalToolLoop`, one line of JSON per call) and answers `ESCALATE` for facts, explanations and writing.
   Every value is checked by the tool (timer 1 s–24 h, real calendar ids), so a wrong guess is refused, not acted on.
   Notion always goes to the cloud: the 8B model misread which item was next too often (10-17).
4. **Cloud brain**: Claude Code (`claude -p`, the user's subscription, default), Codex (`codex exec`, the user's
   ChatGPT plan), the Claude API, or any OpenAI-compatible endpoint. Claude Code runs stripped down (no MCP, skills or
   settings, empty folder): about 1k tokens a question instead of about 138k.
- **Claude's access** (Connections: None / Tools / Full). Tools gives the cloud brain Jarvis's own tools; Claude Code
  reaches them through `Jarvis --tools-mcp`, relayed over a user-only socket to the running app (`ToolRelay`). Full
  adds file and shell tools on the home folder, allowed up front because `claude -p` can't ask.
- Every question starts with the time and the next 7 days' dates (`Persona.context`), so small models look dates up
  instead of working them out.
- **Plans questions** ("what's on Tuesday", "am I free Friday", "what's due this week", "when's my exam") get both
  sources in front of them, decided by word lists (`Toolbox+Plans`): the calendar's events and Notion's due items for
  the days asked about, and Claude gets the Notion tools too. Before (10-17), "what's on" saw only the calendar and
  "what's due" only Notion, so the answer changed with the wording. Not every question: the tools cost tokens and
  time on each one. A named weekday means that day (it used to mean today and tomorrow).
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
- **Timers** live in Jarvis. **Reminders** go to the Reminders app (EventKit), so they sync and ring on the phone:
  why Jarvis had stopped doing reminders with its own timers (10-17). **Alarms** go to the Clock app through the
  user's "Jarvis Alarm" shortcut (Get Dates from Input › Create Alarm), run with `/usr/bin/shortcuts`: macOS has no
  API for Clock alarms, but Shortcuts' Create Alarm action reaches it. Without the shortcut, Jarvis says how to make it.
- **Siri**: a shortcut the user makes ("Ask Jarvis": Dictate Text › URL Encode › Open URLs) opens
  `jarvis://ask?q=...` (`SiriLink`); the notch opens and the answer is spoken. Not App Intents: those need Xcode's
  build step for Siri to find them, and Jarvis is a plain Swift package.
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
  Setup/    Mac advice, Claude Code and Codex setup, Updater, Siri link
  Tools/    timers, reminders, alarms and shortcuts, screen text, calendar, Notion, camera, maths, Mac tools, MCP server
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
