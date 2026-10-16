import Foundation
import JarvisKit
import Testing

struct NowPlayingTests {
    @Test func readsMusicNotification() {
        let info: [AnyHashable: Any] = ["Name": "Song", "Artist": "Band", "Player State": "Playing"]
        #expect(NowPlaying.from(notification: info, player: .music)
                == NowPlaying(title: "Song", artist: "Band", isPlaying: true, player: .music))
    }

    @Test func stoppedMeansNothingPlaying() {
        #expect(NowPlaying.from(notification: ["Player State": "Stopped"], player: .spotify) == nil)
        #expect(NowPlaying.from(script: "", player: .music) == nil)
    }

    @Test func readsScriptOutput() {
        let playing = NowPlaying.from(script: "Song\nBand\npaused", player: .spotify)
        #expect(playing?.title == "Song")
        #expect(playing?.isPlaying == false)
    }
}

struct WeatherTests {
    @Test func parsesForecast() throws {
        let json = #"{"current":{"time":"2026-10-13T14:00","interval":900,"temperature_2m":12.6,"weather_code":3,"is_day":1}}"#
        let report = try OpenMeteoWeather.parseForecast(Data(json.utf8), unit: .celsius)
        #expect(report.temperatureText == "13°")
        #expect(report.condition == "Cloudy")
        #expect(report.symbol == "cloud.fill")
    }

    @Test func parsesGeocodeAndHandlesNoMatch() throws {
        let hit = #"{"results":[{"name":"Toronto","latitude":43.7,"longitude":-79.4}]}"#
        #expect(try OpenMeteoWeather.parseGeocode(Data(hit.utf8))?.name == "Toronto")
        #expect(try OpenMeteoWeather.parseGeocode(Data("{}".utf8)) == nil)
    }

    @Test func headlineAndDetail() throws {
        let json = #"{"current":{"temperature_2m":24.2,"apparent_temperature":25.4,"weather_code":1,"is_day":1}}"#
        let report = try OpenMeteoWeather.parseForecast(Data(json.utf8), unit: .celsius)
        #expect(report.headline == "it's warm")
        #expect(report.detailText == "24° · feels 25°")
        #expect(WeatherReport(temperature: 5, unit: .celsius, code: 63, isDay: true).headline == "it's raining")
        #expect(WeatherReport(temperature: 50, unit: .fahrenheit, code: 0, isDay: true).headline == "it's cool")
    }

    @Test func nightUsesMoon() {
        #expect(WeatherReport(temperature: 5, unit: .celsius, code: 0, isDay: false).symbol == "moon.stars.fill")
    }
}

@MainActor
final class FakePlayer: NowPlayingSource {
    var currentValue: NowPlaying?
    var currentCalls = 0
    var onChange: (@MainActor (NowPlaying?) -> Void)?

    func observe(_ onChange: @escaping @MainActor (NowPlaying?) -> Void) { self.onChange = onChange }
    func current() -> NowPlaying? { currentCalls += 1; return currentValue }
    func playPause(_ player: MusicPlayer?) {}
    func next(_ player: MusicPlayer?) {}
    func previous(_ player: MusicPlayer?) {}
    var opened: [MusicPlayer?] = []
    func open(_ player: MusicPlayer?) { opened.append(player) }
    var played: [String] = []
    func play(_ query: String, in player: MusicPlayer) -> String {
        played.append(query)
        return "Playing \(query)."
    }
}

@MainActor
final class FakeWeather: WeatherSource {
    var cities: [String?] = []
    func current(city: String?) async throws -> WeatherReport {
        cities.append(city)
        return WeatherReport(temperature: 20, unit: .celsius, code: 0, isDay: true, place: city)
    }
}

@MainActor
struct WidgetFeedTests {
    @Test func asksPlayerOnceThenFollowsNotifications() {
        let state = AppState()
        let player = FakePlayer()
        player.currentValue = NowPlaying(title: "A", artist: "B", isPlaying: true, player: .music)
        let feed = WidgetFeed(state: state, player: player, weather: FakeWeather())
        feed.start()
        feed.panelOpened()
        feed.panelOpened()
        #expect(player.currentCalls == 1)
        #expect(state.nowPlaying?.title == "A")
        player.onChange?(nil)
        #expect(state.nowPlaying == nil)
    }

    @Test func weatherRefreshesWhenStaleOrCityChanges() async {
        let state = AppState()
        let weather = FakeWeather()
        let feed = WidgetFeed(state: state, player: FakePlayer(), weather: weather)
        let start = Date()
        feed.panelOpened(now: start)
        feed.panelOpened(now: start.addingTimeInterval(60))
        await Task.yield()
        #expect(weather.cities == [nil])

        state.update { $0.weatherCity = "Toronto" }
        feed.panelOpened(now: start.addingTimeInterval(120))
        feed.panelOpened(now: start.addingTimeInterval(120 + WidgetFeed.weatherMaxAge))
        for _ in 0..<5 { await Task.yield() }
        #expect(weather.cities == [nil, "Toronto", "Toronto"])
        #expect(state.weather?.place == "Toronto")
    }
}

struct TodayListTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T15:00:00Z")!

    private func event(_ id: String, endsInMinutes: Int, allDay: Bool = false) -> AgendaItem {
        AgendaItem(id: id, title: id, start: now.addingTimeInterval(TimeInterval((endsInMinutes - 60) * 60)),
                   end: now.addingTimeInterval(TimeInterval(endsInMinutes * 60)), allDay: allDay)
    }

    @Test func passedEventsAreMarkedButStillListed() {
        let rows = TodayList.rows(agenda: [event("morning", endsInMinutes: -120), event("later", endsInMinutes: 90),
                                           event("holiday", endsInMinutes: -600, allDay: true)],
                                  due: [], now: now)
        #expect(rows.map(\.id) == ["morning", "later", "holiday"])
        #expect(rows.map(\.isPast) == [true, false, false], "all-day never goes grey")
    }

    @Test func dueItemsGoGreyOnlyOnceTheirTimePasses() {
        let early = DueItem(id: "a", title: "Notebook", due: now.addingTimeInterval(-3600), hasTime: true, source: "S")
        let dateOnly = DueItem(id: "b", title: "PS2", due: now.addingTimeInterval(-3600), hasTime: false, source: "S")
        let rows = TodayList.rows(agenda: [], due: [early, dateOnly], now: now)
        #expect(rows.map(\.isPast) == [true, false])
        #expect(rows.last?.when == "All day")
    }

    @Test func overdueItemsAreGreyWithTheirDay() {
        let late = DueItem(id: "c", title: "Lab", due: now.addingTimeInterval(-2 * 86_400), hasTime: false, source: "S")
        let rows = TodayList.rows(agenda: [], due: [late], now: now)
        #expect(rows.first?.isPast == true)
        #expect(rows.first?.when == late.due.formatted(.dateTime.month(.abbreviated).day()))
    }

    @Test func tooManyRowsDropTheOldestPassedFirst() {
        let agenda = (0..<10).map { event("e\($0)", endsInMinutes: $0 < 4 ? -60 * (4 - $0) : 60 * ($0 - 3)) }
        let rows = TodayList.rows(agenda: agenda, due: [], now: now, max: 8)
        #expect(rows.count == 8)
        #expect(rows.first?.id == "e2", "e0 and e1 (earliest passed) were dropped")
    }
}

struct TimerListTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T15:00:00Z")!

    @Test func timersCountDownAndAlarmsShowTheirTime() {
        let timer = JarvisTimer(seconds: 300, ends: now.addingTimeInterval(299.5))
        let reminder = JarvisTimer(seconds: 3600, ends: now.addingTimeInterval(3600), note: "call mom")
        let alarm = JarvisTimer(seconds: 86_000, ends: now.addingTimeInterval(86_000), alarm: true)
        let rows = TimerList.rows([timer, reminder, alarm], now: now)
        #expect(rows.map(\.title) == ["5 minute timer", "Call mom", "Alarm"])
        #expect(rows[0].value == "5:00")
        #expect(rows[2].value.hasSuffix("tomorrow"))
        #expect(TimerList.countdown(3725) == "1:02:05")
    }
}

@MainActor
struct OpenPlayerTests {
    @Test func opensTheAppThatIsPlaying() {
        let state = AppState()
        let player = FakePlayer()
        let feed = WidgetFeed(state: state, player: player, weather: FakeWeather())
        state.setNowPlaying(NowPlaying(title: "A", artist: "B", isPlaying: true, player: .spotify))
        feed.openPlayer()
        #expect(player.opened == [.spotify])
    }
}

struct MorningBriefTests {
    @Test func knowsWhatsAsked() {
        #expect(MorningBrief.ask("good morning") == .morning)
        #expect(MorningBrief.ask("morning jarvis") == .morning)
        #expect(MorningBrief.ask("what's the weather like") == .weather)
        #expect(MorningBrief.ask("do I need an umbrella today") == .weather)
        #expect(MorningBrief.ask("what's the weather in Paris") == nil, "somewhere else: a brain answers")
        #expect(MorningBrief.ask("will it rain tomorrow") == nil, "a forecast: a brain answers")
        #expect(MorningBrief.ask("good morning, can you write my essay intro") == nil)
    }

    @Test func saysWhatToWearNotTheNumber() {
        let report = WeatherReport(temperature: 9, unit: .celsius, code: 3, isDay: true, feelsLike: 7, wind: 30, high: 15,
                                   precipitationChance: 70)
        let text = MorningBrief.weather(report)
        #expect(text == "It's cool out, so grab a jacket or a sweater. Overcast, breezy and rain is likely, so take an umbrella.")
        #expect(!text.contains("°"))
    }

    @Test func countsTodayAndPicksTheBigThings() {
        let now = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        let at = { (hour: Int) in Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now)! }
        let events = [AgendaItem(id: "1", title: "PHY224 lecture", start: at(10), end: at(11), allDay: false),
                      AgendaItem(id: "2", title: "Gym", start: at(18), end: at(19), allDay: false),
                      AgendaItem(id: "3", title: "Breakfast", start: at(6), end: at(7), allDay: false)]
        let due = [DueItem(id: "a", title: "Lab report", due: at(23), hasTime: true, source: "Coursework"),
                   DueItem(id: "b", title: "Chem quiz", due: at(14), hasTime: true, source: "Exams")]
        let text = MorningBrief.text(now: now, weather: nil, events: events, due: due, calendarOn: true)
        #expect(text.hasPrefix("Good morning. It's "))
        #expect(text.contains("You have 2 things on your calendar today."), "the one already over isn't counted")
        #expect(text.contains("Don't forget Chem quiz at"), "exams first")
        #expect(text.contains("and Lab report at"))
    }
}
