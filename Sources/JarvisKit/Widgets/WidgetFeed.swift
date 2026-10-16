import Foundation

/// Keeps the notch's music, weather, today's events and what's due in `AppState` fresh. Work happens only
/// when the panel opens (weather at most every 30 minutes) or a player broadcasts a change.
@MainActor
public final class WidgetFeed {
    public static let weatherMaxAge: TimeInterval = 30 * 60
    /// Notion is asked at most this often (opening the panel triggers it), and in the background never.
    public static let dueMaxAge: TimeInterval = 10 * 60
    /// Only what's due today.
    public static let dueDays = 1

    private let state: AppState
    private let player: NowPlayingSource
    private let weather: WeatherSource
    private let calendar: CalendarSource?
    private let notion: @MainActor () -> NotionAPI?
    private var lastDueFetch: Date?
    private var lastWeatherFetch: (date: Date, city: String)?
    private var askedPlayer = false

    public init(state: AppState, player: NowPlayingSource, weather: WeatherSource, calendar: CalendarSource? = nil,
                notion: @escaping @MainActor () -> NotionAPI? = { nil }) {
        self.state = state
        self.player = player
        self.weather = weather
        self.calendar = calendar
        self.notion = notion
    }

    public func start() {
        player.observe { [weak self] playing in
            self?.state.setNowPlaying(playing)
        }
    }

    public func panelOpened(now: Date = .now) {
        // Notifications only arrive on change, so ask once for what is already playing.
        if !askedPlayer, state.nowPlaying == nil {
            askedPlayer = true
            state.setNowPlaying(player.current())
        }
        refreshWeather(now: now)
        refreshAgenda(now: now)
        refreshDue(now: now)
    }

    func refreshDue(now: Date) {
        guard let api = notion() else {
            if !state.due.isEmpty { state.setDue([]) }
            return
        }
        if let last = lastDueFetch, now.timeIntervalSince(last) < Self.dueMaxAge { return }
        lastDueFetch = now
        Task {
            do {
                state.setDue(try await api.dueItems(days: Self.dueDays, now: now) ?? [])
            } catch {
                lastDueFetch = nil
            }
        }
    }

    /// All of today's events (the ones already over are greyed out by the notch). Cheap, so done on every open.
    func refreshAgenda(now: Date) {
        guard let calendar else { return }
        let day = Calendar.current.startOfDay(for: now)
        let events = calendar.events(from: day, to: day.addingTimeInterval(86_400)) ?? []
        state.setAgenda(events)
    }

    public func playPause() {
        player.playPause(state.nowPlaying?.player)
    }

    /// Opens the app that's playing the song.
    public func openPlayer() {
        player.open(state.nowPlaying?.player)
    }

    public func previous() {
        player.previous(state.nowPlaying?.player)
    }

    public func next() {
        player.next(state.nowPlaying?.player)
    }

    func refreshWeather(now: Date) {
        let city = state.settings.weatherCity.trimmingCharacters(in: .whitespaces)
        if let last = lastWeatherFetch, last.city == city, now.timeIntervalSince(last.date) < Self.weatherMaxAge {
            return
        }
        lastWeatherFetch = (now, city)
        Task {
            do {
                state.setWeather(try await weather.current(city: city.isEmpty ? nil : city))
            } catch {
                // Try again on the next open rather than waiting out the 30 minutes.
                lastWeatherFetch = nil
            }
        }
    }
}
