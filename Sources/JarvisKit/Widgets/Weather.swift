import Foundation

public enum TemperatureUnit: String, Sendable {
    case celsius, fahrenheit

    /// Fahrenheit for US-style locales, Celsius everywhere else.
    public static var local: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

public struct WeatherReport: Equatable, Sendable {
    public var temperature: Double
    public var unit: TemperatureUnit
    /// WMO weather code, as Open-Meteo reports it.
    public var code: Int
    public var isDay: Bool
    /// City name when the user picked one; nil for "current location".
    public var place: String?
    /// Apparent temperature, when the source gives it.
    public var feelsLike: Double?

    public init(temperature: Double, unit: TemperatureUnit, code: Int, isDay: Bool,
                place: String? = nil, feelsLike: Double? = nil) {
        self.feelsLike = feelsLike
        self.temperature = temperature
        self.unit = unit
        self.code = code
        self.isDay = isDay
        self.place = place
    }

    public var temperatureText: String { "\(Int(temperature.rounded()))°" }

    /// "24° · feels 25°"
    public var detailText: String {
        guard let feelsLike else { return temperatureText }
        return "\(temperatureText) · feels \(Int(feelsLike.rounded()))°"
    }

    /// One friendly line, like "it's warm" or "it's raining".
    public var headline: String {
        switch code {
        case 45, 48: return "it's foggy"
        case 51...57: return "it's drizzling"
        case 61...67, 80...82: return "it's raining"
        case 71...77, 85, 86: return "it's snowing"
        case 95...99: return "thunderstorms"
        default: break
        }
        let celsius = unit == .celsius ? temperature : (temperature - 32) * 5 / 9
        switch celsius {
        case ..<0: return "it's freezing"
        case ..<10: return "it's cold"
        case ..<17: return "it's cool"
        case ..<22: return "it's mild"
        case ..<28: return "it's warm"
        default: return "it's hot"
        }
    }

    public var condition: String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77, 85, 86: "Snow"
        case 80...82: "Showers"
        case 95...99: "Thunderstorm"
        default: "—"
        }
    }

    /// SF Symbol for the condition.
    public var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }
}

public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Where weather comes from.
@MainActor
public protocol WeatherSource {
    /// Weather for `city`, or for this Mac's location when nil.
    func current(city: String?) async throws -> WeatherReport
}

/// Where this Mac is.
@MainActor
public protocol Locator {
    func coordinate() async throws -> Coordinate
}
