import Foundation

/// What the notch shows on a display without a hardware notch, one line at a time, fading from one to the next,
/// so the bar there isn't just black.
public enum TickerItem: String, Codable, Sendable, CaseIterable, Identifiable {
    case time, date, music, battery, weather, nextEvent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .time: "Time"
        case .date: "Date"
        case .music: "What's playing"
        case .battery: "Battery"
        case .weather: "Weather"
        case .nextEvent: "Next event"
        }
    }
}

public enum Ticker {
    /// The lines to cycle through, in `items` order. Ones with nothing to say (no song playing, no battery, no
    /// event left today) are left out.
    public static func lines(_ items: [TickerItem], now: Date, nowPlaying: NowPlaying?, battery: Battery?,
                             weather: WeatherReport?, agenda: [AgendaItem]) -> [String] {
        items.compactMap { item in
            switch item {
            case .time:
                return now.formatted(date: .omitted, time: .shortened)
            case .date:
                return now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            case .music:
                guard let song = nowPlaying, song.isPlaying else { return nil }
                return song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)"
            case .battery:
                guard let battery else { return nil }
                return "\(battery.percent)%" + (battery.charging ? " charging" : "")
            case .weather:
                guard let weather else { return nil }
                return "\(Int(weather.temperature.rounded()))° \(MorningBrief.sky(weather))"
            case .nextEvent:
                guard let next = agenda.filter({ !$0.allDay && $0.start > now }).min(by: { $0.start < $1.start })
                else { return nil }
                return "\(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)"
            }
        }
    }
}
