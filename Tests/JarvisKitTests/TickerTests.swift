import Foundation
import JarvisKit
import Testing

struct TickerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func keepsTheOrderAndSkipsWhatHasNothingToSay() {
        let song = NowPlaying(title: "Song", artist: "Band", isPlaying: true, player: .music)
        let lines = Ticker.lines([.music, .battery, .nextEvent], now: now, nowPlaying: song, battery: nil,
                                 weather: nil, agenda: [])
        #expect(lines == ["Song · Band"])
    }

    @Test func pausedMusicIsSkipped() {
        let song = NowPlaying(title: "Song", artist: "Band", isPlaying: false, player: .music)
        #expect(Ticker.lines([.music], now: now, nowPlaying: song, battery: nil, weather: nil, agenda: []).isEmpty)
    }

    @Test func nextEventIsTheSoonestStillToCome() {
        let past = AgendaItem(id: "a", title: "Gone", start: now - 3600, end: now - 1800, allDay: false)
        let later = AgendaItem(id: "b", title: "Later", start: now + 7200, end: now + 9000, allDay: false)
        let soon = AgendaItem(id: "c", title: "Soon", start: now + 600, end: now + 1200, allDay: false)
        let line = Ticker.lines([.nextEvent], now: now, nowPlaying: nil, battery: nil, weather: nil,
                                agenda: [past, later, soon])
        #expect(line.first?.hasSuffix("Soon") == true)
    }

    @Test func batterySaysWhenCharging() {
        let lines = Ticker.lines([.battery], now: now, nowPlaying: nil, battery: Battery(percent: 80, charging: true),
                                 weather: nil, agenda: [])
        #expect(lines == ["80% charging"])
    }
}
