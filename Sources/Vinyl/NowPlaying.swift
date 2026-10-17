import AppKit

enum Player: String {
    case spotify, music
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var appName: String { self == .spotify ? "Spotify" : "Music" }
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var notification: Notification.Name {
        Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var player: Player
    var spotifyID: String?
    var key: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

/// AppleScript runs on one background queue so a permission prompt never freezes the UI.
enum Script {
    static let queue = DispatchQueue(label: "vinyl.applescript")

    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

/// Follows Spotify and Apple Music through the notifications both apps broadcast locally.
final class NowPlayingMonitor {
    var onChange: ((Track?, Bool) -> Void)?
    private(set) var track: Track?
    private(set) var isPlaying = false
    private var active: Player?

    func start() {
        let center = DistributedNotificationCenter.default()
        for player in [Player.spotify, .music] {
            center.addObserver(forName: player.notification, object: nil, queue: .main) { [weak self] note in
                self?.handle(note.userInfo ?? [:], from: player)
            }
            if player.isRunning { queryInitial(player) }
        }
    }

    private func handle(_ info: [AnyHashable: Any], from player: Player) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        let title = info["Name"] as? String ?? ""
        let nowPlaying = state == "playing"

        if nowPlaying, !title.isEmpty {
            active = player
            var id = info["Track ID"] as? String
            if let s = id, s.hasPrefix("spotify:track:") { id = String(s.dropFirst("spotify:track:".count)) } else { id = nil }
            update(Track(title: title, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                         player: player, spotifyID: player == .spotify ? id : nil), playing: true)
        } else if active == player || active == nil {
            update(track, playing: false)
        }
    }

    private func update(_ t: Track?, playing: Bool) {
        guard t != track || playing != isPlaying else { return }
        track = t
