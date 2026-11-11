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

/// Live weather for Waterloo, Ontario from Open-Meteo. No account, no key, no location lookup.
final class WeatherService {
    static let waterloo = (43.46, -80.52)
    var onUpdate: ((WeatherReading) -> Void)?
    private var timer: Timer?
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
            guard let reading = await conditions(at: Self.waterloo) else { return }
            await MainActor.run { self.onUpdate?(reading) }
        }
    }

    private func json(_ string: String) async -> [String: Any]? {
        guard let url = URL(string: string), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func conditions(at place: (Double, Double)) async -> WeatherReading? {
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(place.0)&longitude=\(place.1)&current=temperature_2m,weather_code"
        guard let d = await json(url), let current = d["current"] as? [String: Any],
              let code = current["weather_code"] as? Int, let temp = current["temperature_2m"] as? Double else { return nil }
        return WeatherReading(weather: Weather(wmo: code), celsius: temp)
    }
}
