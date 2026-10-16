import CoreLocation

/// This Mac's location from Location Services. Asks permission the first time.
@MainActor
public final class CurrentLocation: NSObject, Locator, CLLocationManagerDelegate {
    public enum Failure: Error {
        case denied
    }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Coordinate, Error>] = []

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func coordinate() async throws -> Coordinate {
        if let recent = manager.location, -recent.timestamp.timeIntervalSinceNow < 3600 {
            return Coordinate(recent)
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            ask()
        }
    }

    private func ask() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(Failure.denied))
        default: manager.requestLocation()
        }
    }

    private func finish(_ result: Result<Coordinate, Error>) {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(with: result) }
    }

    // MARK: CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let decided = manager.authorizationStatus != .notDetermined
        MainActor.assumeIsolated {
            if !waiting.isEmpty, decided { ask() }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(last)
        MainActor.assumeIsolated { finish(.success(coordinate)) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}

extension Coordinate {
    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
