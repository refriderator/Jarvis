import Foundation

/// Weather from Open-Meteo: free, no account or key.
@MainActor
public struct OpenMeteoWeather: WeatherSource {
    public enum Failure: Error {
        case cityNotFound
    }

    private let locator: Locator
    private let unit: TemperatureUnit

    public init(locator: Locator, unit: TemperatureUnit = .local) {
        self.locator = locator
        self.unit = unit
    }

    public func current(city: String?) async throws -> WeatherReport {
        var place: String?
        let coordinate: Coordinate
        if let city {
            let found = try await geocode(city)
            coordinate = found.coordinate
            place = found.name
        } else {
            coordinate = try await locator.coordinate()
        }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "temperature_unit", value: unit.rawValue),
        ]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        var report = try Self.parseForecast(data, unit: unit)
        report.place = place
        return report
    }

    private func geocode(_ city: String) async throws -> (name: String, coordinate: Coordinate) {
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        guard let found = try Self.parseGeocode(data) else { throw Failure.cityNotFound }
        return found
    }

    // MARK: Parsing (static so tests can feed it sample responses)

    nonisolated public static func parseForecast(_ data: Data, unit: TemperatureUnit) throws -> WeatherReport {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let apparent_temperature: Double?
                let weather_code: Int
                let is_day: Int
            }
            let current: Current
        }
        let current = try JSONDecoder().decode(Response.self, from: data).current
        return WeatherReport(temperature: current.temperature_2m, unit: unit,
                             code: current.weather_code, isDay: current.is_day == 1,
                             feelsLike: current.apparent_temperature)
    }

    nonisolated public static func parseGeocode(_ data: Data) throws -> (name: String, coordinate: Coordinate)? {
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
            }
            let results: [Result]?
        }
        guard let first = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return (first.name, Coordinate(latitude: first.latitude, longitude: first.longitude))
    }
}
