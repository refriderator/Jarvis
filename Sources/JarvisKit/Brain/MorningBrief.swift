import Foundation

/// "Good morning" / "morning Jarvis": the day in a few spoken sentences, by code and no model. The date, what to wear
/// (never the number), the sky, wind and rain, how many events are left today, and the one or two biggest things.
/// Weather questions ("what's the weather", "do I need an umbrella") get just the weather part.
public enum MorningBrief {
    public enum Ask: Equatable, Sendable {
        case morning, weather
    }

    private static let morning = try! NSRegularExpression(
        pattern: #"^\W*(?:(?:good\s+)?morning|morning\s+brief(?:ing)?|brief\s+me|what'?s\s+my\s+day\s+(?:look(?:ing)?\s+)?like)\b(?:\s+\w+)?\W*$"#,
        options: .caseInsensitive)
    private static let weather = try! NSRegularExpression(
        pattern: #"\b(weather|forecast|umbrella|jacket|coat|(?:will|is)\s+it\s+(?:going\s+to\s+)?(?:rain|snow)|how\s+(?:hot|cold|warm)\s+is\s+it|what\s+should\s+i\s+wear)\b"#,
        options: .caseInsensitive)

    /// What's being asked, or nil when it isn't either. Weather elsewhere ("weather in Paris") is left to a brain.
    public static func ask(_ text: String) -> Ask? {
        let range = NSRange(text.startIndex..., in: text)
        if morning.firstMatch(in: text, range: range) != nil { return .morning }
        guard weather.firstMatch(in: text, range: range) != nil,
              text.range(of: #"\b(in|at|for)\s+[A-Z]"#, options: .regularExpression) == nil,
              text.range(of: #"\b(yesterday|tomorrow|weekend|next week)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return .weather
    }

    /// The whole brief. `events` are today's, `due` what Notion has for today (both may be empty).
    public static func text(now: Date, weather: WeatherReport?, events: [AgendaItem], due: [DueItem],
                            calendarOn: Bool) -> String {
        var parts = ["Good \(greeting(now)). It's \(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))."]
        parts.append(weather.map(Self.weather) ?? "I couldn't get the weather.")
        let left = events.filter { $0.allDay || $0.end > now }.sorted { $0.start < $1.start }
        if calendarOn {
            parts.append(left.isEmpty ? "Nothing's on your calendar for the rest of today."
                         : "You have \(left.count) thing\(left.count == 1 ? "" : "s") on your calendar today.")
        }
        let big = bigItems(events: left, due: due, now: now)
        if !big.isEmpty { parts.append("Don't forget " + list(big) + ".") }
        return parts.joined(separator: " ")
    }

    /// "It's cool out, so grab a light jacket. Partly cloudy, a light breeze, and rain is likely, so take an umbrella."
    public static func weather(_ report: WeatherReport) -> String {
        let celsius = { (value: Double) in report.unit == .celsius ? value : (value - 32) * 5 / 9 }
        // What it feels like now, nudged toward the day's high so a cold morning that warms up isn't a winter coat.
        let feel = celsius(report.feelsLike ?? report.temperature)
        let day = report.high.map { (feel + celsius($0)) / 2 } ?? feel
        var sentence = "It's " + wear(day) + "."
        var sky = [sky(report)]
        if let wind = report.wind { sky.append(Self.wind(report.unit == .celsius ? wind : wind * 1.609)) }
        if let chance = report.precipitationChance { sky.append(rain(chance, snow: day < 1 || (71...86).contains(report.code))) }
        sentence += " " + list(sky).prefix(1).uppercased() + list(sky).dropFirst() + "."
        return sentence
    }

    static func wear(_ celsius: Double) -> String {
        switch celsius {
        case ..<(-10): "bitterly cold out, so wear a winter coat, hat and gloves"
        case ..<0: "freezing out, so bundle up in a winter coat"
        case ..<8: "cold out, so wear a warm coat"
        case ..<15: "cool out, so grab a jacket or a sweater"
        case ..<20: "mild out, so a long sleeve or a light jacket will do"
        case ..<27: "warm out, so it's t-shirt weather"
        default: "hot out, so dress light and drink water"
        }
    }

    static func sky(_ report: WeatherReport) -> String {
        switch report.code {
        case 0: report.isDay ? "sunny" : "clear"
        case 1: report.isDay ? "mostly sunny" : "mostly clear"
        case 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "foggy"
        case 51...57: "drizzly"
        case 61...67: "rainy"
        case 71...77, 85, 86: "snowing"
        case 80...82: "showery"
        case 95...99: "stormy"
        default: "cloudy"
        }
    }

    static func wind(_ kmh: Double) -> String {
        switch kmh {
        case ..<10: "calm"
        case ..<25: "a light breeze"
        case ..<40: "breezy"
        case ..<60: "windy"
        default: "very windy"
        }
    }

    static func rain(_ chance: Int, snow: Bool) -> String {
        let what = snow ? "snow" : "rain"
        switch chance {
        case ..<20: return "no \(what) expected"
        case ..<50: return "a small chance of \(what)"
        default: return "\(what) is likely, so " + (snow ? "wear boots" : "take an umbrella")
        }
    }

    /// One or two things worth remembering: exams and tests due today first, then anything else due, then the next event.
    static func bigItems(events: [AgendaItem], due: [DueItem], now: Date) -> [String] {
        let today = due.filter { Calendar.current.isDate($0.due, inSameDayAs: now) }
        let exams = today.filter { $0.title.range(of: #"\b(exam|midterm|test|quiz|final)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
        var picked = (exams + today.filter { !exams.contains($0) }).prefix(2).map { item in
            item.title + (item.hasTime ? " at " + item.due.formatted(date: .omitted, time: .shortened) : " today")
        }
        if picked.count < 2, let next = events.first(where: { !$0.allDay && $0.start > now }) {
            picked.append(next.title + " at " + next.start.formatted(date: .omitted, time: .shortened))
        }
        return Array(picked.prefix(2))
    }

    static func greeting(_ now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case ..<12: "morning"
        case ..<17: "afternoon"
        default: "evening"
        }
    }

    /// "a", "a and b", "a, b and c"
    static func list(_ items: [String]) -> String {
        items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
