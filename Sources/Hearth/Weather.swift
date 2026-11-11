import Foundation

/// What the sky outside the window is doing.
enum Weather: String, CaseIterable {
    case clear, partly, cloudy, fog, rain, snow, storm

    var title: String {
        switch self {
        case .clear: return "Clear"
        case .partly: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .storm: return "Storm"
        }
    }

    /// How much direct sun still reaches the room.
    var sunFactor: CGFloat {
        switch self {
        case .clear: return 1
        case .partly: return 0.8
        case .cloudy: return 0.22
        case .fog: return 0.15
        case .snow: return 0.25
        case .rain: return 0.08
        case .storm: return 0.03
        }
    }

    var isPrecipitating: Bool { self == .rain || self == .snow || self == .storm }

    /// WMO weather interpretation codes, as returned by Open-Meteo.
    init(wmo code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partly
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        case 51...67, 80...82: self = .rain
        default: self = .cloudy
        }
    }
}

struct WeatherReading: Equatable {
    var weather: Weather
    var celsius: Double
}

/// Live weather with no account and no key: a coarse location from the public IP address
/// (ipwho.is), then current conditions for that spot from Open-Meteo.
final class WeatherService {
    var onUpdate: ((WeatherReading) -> Void)?
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        Task {
            guard let place = await location(), let reading = await conditions(at: place) else { return }
            await MainActor.run { self.onUpdate?(reading) }
        }
    }

    private func json(_ string: String) async -> [String: Any]? {
        guard let url = URL(string: string), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Latitude and longitude rounded to about 10 km, looked up at most once a day.
    private func location() async -> (Double, Double)? {
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: "placeTime")
        if age < 24 * 3600, defaults.object(forKey: "placeLat") != nil {
            return (defaults.double(forKey: "placeLat"), defaults.double(forKey: "placeLon"))
        }
        guard let d = await json("https://ipwho.is/?fields=success,latitude,longitude"),
              let lat = d["latitude"] as? Double, let lon = d["longitude"] as? Double else {
            // Offline or blocked: fall back to the last place we knew, however old.
            guard defaults.object(forKey: "placeLat") != nil else { return nil }
            return (defaults.double(forKey: "placeLat"), defaults.double(forKey: "placeLon"))
        }
        let rounded = ((lat * 10).rounded() / 10, (lon * 10).rounded() / 10)
        defaults.set(rounded.0, forKey: "placeLat")
        defaults.set(rounded.1, forKey: "placeLon")
        defaults.set(Date().timeIntervalSince1970, forKey: "placeTime")
        return rounded
    }

    private func conditions(at place: (Double, Double)) async -> WeatherReading? {
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(place.0)&longitude=\(place.1)&current=temperature_2m,weather_code"
        guard let d = await json(url), let current = d["current"] as? [String: Any],
              let code = current["weather_code"] as? Int, let temp = current["temperature_2m"] as? Double else { return nil }
        return WeatherReading(weather: Weather(wmo: code), celsius: temp)
    }
}
