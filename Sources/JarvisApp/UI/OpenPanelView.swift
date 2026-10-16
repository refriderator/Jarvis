import JarvisKit
import SwiftUI

/// Contents of the open notch. The top band sits beside the hardware notch: tabs and Settings on the right.
/// Below: big time and weather, the tab's content (Today, Finder, Monitor or Web; or the drop box while a window is
/// dragged in), now playing, the last answer, then the search field. No cards.
struct OpenPanelView: View {
    let state: AppState
    let feed: WidgetFeed
    let assistant: Assistant
    let voice: VoiceSession
    let openSettings: () -> Void
    let cancelTimer: (UUID) -> Void
    let dock: DockController
    let monitor: MonitorFeed
    let browser: BrowserController
    let video: VideoController

    /// From the content's edge (inset 22 pt in the shape, which is the open width, centred on the notch) to
    /// 12 pt right of the hardware notch.
    private var videoButtonX: CGFloat {
        state.layout.size(for: .open).width / 2 + state.layout.notch.width / 2 + 12 - 22
    }

    var body: some View {
        let tint = state.skin.foreground
        VStack(spacing: 10) {
            HStack {
                // Left of the notch: what the dropdown shows (with a video held, clicking the chosen tab folds
                // its content away and back), Keep on the Finder tab, and the next timer while a caption is up.
                PanelTabs(selected: state.layout.hidesContent ? nil : state.dock.tab, tint: tint,
                          accent: state.skin.accent, select: dock.select)
                if state.captionActive, let timer = state.timers.first {
                    Label { TimerCountdown(timer: timer) } icon: { Image(systemName: "timer") }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(state.skin.accent)
                        .help("\(timer.label) timer. Say \"cancel the timer\" to stop it.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                // Video, pinned just right of the notch where the mini notch's tab had it (the dropdown is wide
                // enough that Keep | Large never reaches it).
                // Keep Display right beside it, so the controls sit together, then the Last response tab.
                HStack(spacing: 6) {
                    if state.video.available || state.video.held {
                        VideoButton(held: state.video.held, tint: tint, accent: state.skin.accent,
                                    hold: video.hold, giveBack: video.giveBack,
                                    reach: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .transition(.opacity)
                    }
                    // Always there, so Keep can be turned off from any tab it was turned on in.
                    KeepButton(mode: state.dock.keep, tint: tint,
                               accent: state.skin.accent, select: { dock.setKeep($0); video.sync() })
                    // The "Last response" tab for a minute after an answer, in this row so it never lands on Keep
                    // (on the right edge it slid under Keep Info).
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        if state.lastResponse(now: context.date) != nil {
                            Button(action: state.showLastResponse) {
                                Image(systemName: "text.bubble")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(tint.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Last response")
                            .transition(.opacity)
                        }
                    }
                }
                .offset(x: videoButtonX)
            }
            .overlay(alignment: .trailing) {
                // Right edge: Settings.
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Settings")
            }
            .offset(y: 6)
            .font(.callout)
            .frame(height: state.layout.notch.height + NotchLayout.bandPad)
            .padding(.trailing, 6)

            HStack(alignment: .top) {
                if let size = state.layout.openVideoSize {
                    // With a video: time and weather on the left, a strip of held apps (two across, three down)
                    // centred between them and the video, and the video on the right, down to the search field.
                    // Only as wide as they are, so the strip's place doesn't depend on the music row (which
                    // stretches; it took all the room and pushed the strip against the video).
                    // The left side gets exactly the room left of the video: a long date can't push the video right
                    // (and off its hole) the way it did when they were laid out together.
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            TimeLabel(tint: tint)
                            WeatherLabel(weather: state.weather, tint: tint)
                        }
                        .fixedSize()
                        HeldAppsRow(state: state, dock: dock, columns: 2)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // It shows through a hole in the notch cut here (see VideoController). While a loose video is
                    // dragged in, an outline shows where it'll go.
                    RoundedRectangle(cornerRadius: VideoController.cornerRadius)
                        .strokeBorder(state.skin.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .background(state.skin.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: VideoController.cornerRadius))
                        .overlay { Image(systemName: "pip.enter").font(.title2).foregroundStyle(state.skin.accent) }
                        .opacity(state.video.catching && !state.video.held ? 1 : 0)
                        .frame(width: size.width, height: size.height)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchView.shapeSpace)) }
                            action: { video.slotMoved($0) }
                        .padding(.leading, 8)
                } else {
                    TimeLabel(tint: tint)
                        .fixedSize()
                    HeldAppsRow(state: state, dock: dock)
                        .padding(.leading, 12)
                        .padding(.top, 6)
                    Spacer()
                    WeatherLabel(weather: state.weather, tint: tint)
                }
            }
            .frame(height: state.layout.openVideoSize?.height)
            .overlay(alignment: .bottomLeading) {
                // Music along the bottom, under the strip (three rows leave room there), up to the video.
                if let size = state.layout.openVideoSize {
                    MusicRow(nowPlaying: state.nowPlaying, tint: tint, playPause: feed.playPause,
                             previous: feed.previous, next: feed.next,
                             open: { feed.openPlayer(); state.send(.dismiss) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, size.width + 16)
                }
            }
            // A window being dragged in gets the drop box; otherwise the tab's content, which fades out while a
            // caption is up (the music slides up into its place).
            let showsToday = !state.agenda.isEmpty || !state.due.isEmpty
            if state.dock.dragging != nil {
                DropBox(state: state, dock: dock)
                    .frame(height: state.layout.shelfDepth - 8)
                    .padding(.bottom, NotchLayout.agendaGap)
                    .transition(.opacity)
            } else if state.layout.hidesContent {
                Spacer(minLength: 0)
            } else if !state.captionActive && state.dock.tab == .monitor {
                MonitorView(history: state.stats, skin: state.skin)
                    .frame(height: state.layout.shelfDepth - 8)
                    .padding(.bottom, NotchLayout.agendaGap)
                    .onAppear(perform: monitor.start)
                    .onDisappear(perform: monitor.stop)
                    .transition(.opacity)
            } else if !state.captionActive && state.dock.tab == .browser {
                BrowserView(state: state, browser: browser)
                    .frame(height: state.layout.shelfDepth - 8)
                    .padding(.bottom, NotchLayout.agendaGap)
                    .transition(.opacity)
            } else if !state.captionActive && state.dock.tab == .finder {
                FolderShelfView(state: state, dock: dock)
                    .frame(height: state.layout.shelfDepth - 8)
                    .padding(.bottom, NotchLayout.agendaGap)
                    // Nudged down so the gap above it (music row, or the video when one's held) and the gap above the
                    // search field match better.
                    .offset(y: state.layout.openVideoSize == nil ? 4 : 9)
                    .transition(.opacity)
            } else if !state.captionActive && (showsToday || !state.timers.isEmpty) {
                VStack(alignment: .leading, spacing: 0) {
                    if !state.timers.isEmpty {
                        TimerRows(timers: state.timers, tint: tint, accent: state.skin.accent, cancel: cancelTimer)
                    }
                    if showsToday {
                        AgendaList(agenda: state.agenda, due: state.due, tint: tint)
                    }
                }
                .padding(.bottom, NotchLayout.agendaGap)
                .transition(.opacity)
            } else {
                // No list: flexible space above the music row too, so it sits evenly between the date and
                // the search field instead of hugging the date. With the list, the music hugs the list.
                Spacer(minLength: 0)
            }
            if state.layout.openVideoSize == nil {
                MusicRow(nowPlaying: state.nowPlaying, tint: tint, playPause: feed.playPause,
                         previous: feed.previous, next: feed.next,
                         // Opening the player takes you away from Jarvis, so close the notch too.
                         open: { feed.openPlayer(); state.send(.dismiss) })
            }
            if case .listening(let heard) = state.voice {
                ListeningView(heard: heard, skin: state.skin, hotkey: state.settings.talkHotkey,
                              holding: state.settings.talkMode == .pushToHold,
                              stopsOnPause: state.settings.pauseToSend > 0)
                    .frame(height: state.layout.captionHeight - 10)
                    .transition(.opacity)
            } else if state.captionActive, let turn = state.turns.last {
                CaptionView(turn: turn, skin: state.skin, size: state.settings.captionSize,
                            showTokens: state.settings.showTokens, speaking: state.voice == .speaking,
                            pinned: state.captionPinned, showsSummary: state.showsSummary,
                            togglePin: state.toggleCaptionPin,
                            summarize: { turn.summary == nil ? assistant.summarize() : state.toggleSummary() },
                            useCloud: assistant.useCloud, skipCloud: assistant.skipCloud,
                            stopSpeaking: voice.stopSpeaking)
                    .frame(height: state.layout.captionHeight - 10)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            // Nudged up into the room taken off the panel's height for it, so it sits a little closer to what's
            // above than the even split would put it.
            InputBar(state: state, assistant: assistant, voice: voice)
                .offset(y: -NotchLayout.inputBarLift - NotchLayout.inputBarNudge)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, NotchLayout.inputBarBottom)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: state.captionActive)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: state.captionPinned)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: state.showsSummary)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: state.dock.showsShelf)
        .animation(.easeInOut(duration: 0.25), value: state.dock.tab)
        .animation(.easeInOut(duration: 0.2), value: state.dock.dragging)
    }
}
