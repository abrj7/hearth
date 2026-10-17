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

